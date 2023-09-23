# Trap机制
用户空间和内核空间的切换被称为Trap，通常发生在以下情况：
- 程序执行系统调用
- 程序出现了类似page fault、运算时除以0的错误
- 一个设备触发了中断使得当前程序运行需要响应内核设备驱动

**重要寄存器：**
- PC：程序计数器
- SATP：指向当前页表的物理内存地址
- `stvec`：内核在这里写入其陷阱处理程序的地址；RISC-V跳转到这里处理陷阱
- `sepc`：当发生陷阱时，RISC-V会在这里保存程序计数器`pc`（因为`pc`会被`stvec`覆盖）。`sret`（从陷阱返回）指令会将`sepc`复制到`pc`。内核可以写入`sepc`来控制`sret`的去向
- `scause`： RISC-V在这里放置一个描述陷阱原因的数字
- `sscratch`：内核在这里放置了一个值，这个值在陷阱处理程序一开始就会派上用场
- mode标志位：这个标志位表明了当前是supervisor mode还是user mode。当我们在运行Shell的时候，自然是在user mode

在trap的最开始，CPU的所有状态都设置成运行用户代码而不是内核代码。在trap处理的过程中，我们实际上需要更改一些这里的状态，或者对状态做一些操作。这样我们才可以运行系统内核中普通的C程序。接下来我们先来预览一下需要做的操作：
1. 我们需要保存32个用户寄存器。因为很显然我们需要恢复用户应用程序的执行，尤其是当用户程序随机的被设备中断所打断时。我们希望内核能够响应中断，之后在用户程序完全无感知的情况下再恢复用户代码的执行。
2. 程序计数器也需要在某个地方保存，它几乎跟一个用户寄存器的地位是一样的，我们需要能够在用户程序运行中断的位置继续执行用户程序。
3. 我们需要将mode改成supervisor mode，因为我们想要使用内核中的各种各样的特权指令
4. SATP寄存器现在正指向user page table，而user page table只包含了用户程序所需要的内存映射和一两个其他的映射，它并没有包含整个内核数据的内存映射。所以在运行内核代码之前，我们需要将SATP指向kernel page table。
5. 我们需要将堆栈寄存器指向位于内核的一个地址，因为我们需要一个堆栈来调用内核的C函数。
6. 一旦我们设置好了，并且所有的硬件状态都适合在内核中使用， 我们需要跳入内核的C代码。

**mode标志位：**
当我们在用户空间时，这个标志位对应的是user mode，当我们在内核空间时，这个标志位对应supervisor mode。supervisor mode模式有以下特权：
- 读写控制寄存器
	- 读写SATP寄存器，也就是page table的指针
	- 读写STVEC，也就是处理trap的内核指令地址
	- 读写SEPC，保存当发生trap时的程序计数器
	- 读写SSCRATCH
- 可以使用PTE_U为0的PTE

# Trap代码执行流程（抽象）
以write系统调用为例，对于用户空间，write就是一个C函数调用，但他实际上是通过ECALL来执行指令的。之后在内核中执行的第一个指令就是uservec，该函数在trampoline.s中。之后函数跳转到usertrap函数中，这个函数在trap.c中。在该函数中，我们执行了一个syscall的函数，用于执行write的内核代码。然后我们就要开始返回，先调用同在trap.c中的usertrapret函数，再调用位于trampoline.s中的userret函数。
![[Pasted image 20230923094327.png]]

# Trap代码执行流程（实际）
## ECALL指令之前
我们以sh.c程序中调用write系统调用为例，我们在usys.pl中会生成各个系统调用的关联汇编代码，也就是usys.s。（这就是为什么我们添加系统调用的时候要在这个文件也添加对应入口）

如图示，write函数在用户空间中的代码负责将SYS_write加载到a7寄存器，然后执行ecall指令。
![[Pasted image 20230923104041.png]]

我们在ecall处打上断点，然后查看用户页表如下。这是个非常小的page table，它只包含了6条映射关系。这是用户程序Shell的page table，而Shell是一个非常小的程序，这6条映射关系是有关Shell的指令和数据，以及一个无效的page用来作为guard page，以防止Shell尝试使用过多的stack page。

其中第三条没有设置PTE_U，因而使无效的，是guard page。后两条分别是trapframe page和trampoline page，也是只能在内核模式下运行。
![[Pasted image 20230923104358.png]]


## ECALL指令之后
接下来我们执行ecall指令，通过查看pc寄存器我们发现程序已经跳转到了trampoline page的最开始，这就与上文页表对应了。接下来要执行的代码如下，可以看到我们要小心地保存所有用户寄存器，以便之后进行恢复。
![[Pasted image 20230923104301.png]]

到这里我们先讲讲为什么执行ecall指令后我们跳转到了这里。ecall指令做了以下三件事：
1. ecall将代码从user mode改到supervisor mode
2. ecall将程序计数器的值保存在了SEPC寄存器。
3. ecall会跳转到STVEC寄存器指向的指令。STVEC寄存器存储地就是trampoline page的起始位置。

因而我们保存了中断地址，跳转到了trampoline page地址，同时切换到了内核模式从而能够执行代码。

根据我们开始说的Trap机制，我们还需要做以下事情：
1. 保存32个用户寄存器的内容，这样当我们想要恢复用户代码执行时，我们才能恢复这些寄存器的内容。
2. 现在我们还在user page table，我们需要切换到kernel page table。
3. 创建或者找到一个kernel stack，并将Stack Pointer寄存器的内容指向那个kernel stack。这样才能给C代码提供栈。
4. 需要跳转到内核中C代码的某些合理的位置。

# uservec函数
trampoline page第一个要执行的函数就是uservec函数，该函数首先要做的就是保存用户寄存器。这包含两个部分：
1. XV6在每个user page table映射了trapframe page（内核完成），这样每个进程都有自己的trapframe page。这个page包含了很多有趣的数据，但是现在最重要的数据是用来保存用户寄存器的32个空槽位。
2. 在进入到user space之前，内核会将trapframe page的地址保存在SSCRATCH寄存器中。

这就可以解释为什么trampoline.S函数首先将a0寄存器和SSCRATCH寄存器进行交换，然后a0就保存了trapframe的地址，然后就把所有用户寄存器都保存到trapframe中。

接下来uservec会找到一个kernel stack，看以下代码。高亮处的指令将a0指向的内存地址往后数的第8个字节开始的数据加载到Stack Pointer寄存器。a0的内容现在是trapframe page的地址，从本节第一张图中，trapframe的格式可以看出，第8个字节开始的数据是内核的Stack Pointer（kernel_sp）。这样我们就找到了进程的内核栈地址（共享全局内核页表）。
![[Pasted image 20230923111906.png]]

接下来uservec函数将CPU核的编号也就是hartid保存在tp寄存器上，也就是如下代码：
![[Pasted image 20230923112229.png]]

然后我们加载出usertrap函数的地址和内核页表的地址，代码如下：
![[Pasted image 20230923112505.png]]

然后我们将satp寄存器设置成内核页表的地址，并准备跳转到我们需要执行的usertrap函数。
![[Pasted image 20230923112638.png]]

这里解释一下为什么切换satp寄存器后，程序没有崩溃。因为在内核页表和用户页表中，trampline page都映射了同一位置。之所以叫trampoline page，是因为你某种程度在它上面“弹跳”了一下，然后从用户空间走到了内核空间。（确实很形象）

接下来我们就要以kernel stack，kernel page table跳转到usertrap函数。

# usertrap函数
