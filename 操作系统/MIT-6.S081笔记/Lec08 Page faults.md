# Page Fault Basics
这一节的主要内容就是page fault以及通过page fault可以实现的一系列虚拟内存功能。包含以下主题：
- lazy allocation
- copy-on-write fork
- demand paging
- memory mapped files

在未经修改的XV6中，一旦用户空间进程触发了page fault，会导致进程被杀掉。这是非常保守的处理方式。但事实上page fault可以让我们实现一些有趣的事情。

我们先来考虑内核需要什么信息来响应page fault：
- 我们需要出错的虚拟地址，或者是触发page fault的源。当出现page fault的时候，XV6内核会打印出错的虚拟地址，并且这个地址会被保存在STVAL寄存器中
- 我们需要知道的第二个信息是出错的原因，我们或许想要对不同场景的page fault有不同的响应。不同的场景是指，比如因为load指令触发的page fault、因为store指令触发的page fault又或者是因为jump指令触发的page fault。这些原因会保存在SCAUSE寄存器中（保存了trap机制中进入到supervisor mode的原因）
- 我们或许想要知道的第三个信息是触发page fault的指令的地址。作为trap处理代码的一部分，这个地址存放在SEPC（Supervisor Exception Program Counter）寄存器中，并同时会保存在trapframe->epc（注，详见lec06）中。

以下是触发trap机制的原因，可以看到三个page fault对应的错误代码分别是12、13、15
![[Pasted image 20230925174928.png]]


所以，从硬件和XV6的角度来说，当出现了page fault，现在有了3个对我们来说极其有价值的信息，分别是：
- 引起page fault的内存地址
- 引起page fault的原因类型
- 引起page fault时的程序计数器值，这表明了page fault在用户空间发生的位置。这样我们就可以修复page table，并重新执行对应的指令。

# Lazy page allocation
sbrk是XV6提供的系统调用，它使得用户应用程序能扩大自己的heap。当一个应用程序启动的时候，sbrk指向的是heap的最底端，同时也是stack的最顶端。这个位置通过代表进程的数据结构中的sz字段表示，这里以p->sz表示（我们曾在Lab3中用过）

注意，heap是向上扩展的，因而p->sz就标识了堆的大小，同时也是整个用户页表的大小。
![[Pasted image 20230925173858.png]]

从sbrk代码可以看出，sbrk先从参数中读取需要扩展的字节数，然后调用growproc函数进行扩展。这里即可以扩展字节，也可以缩减字节。
```C
uint64
sys_sbrk(void)
{
  int addr;
  int n;

  if(argint(0, &n) < 0)
    return -1;
  addr = myproc()->sz;
  if(growproc(n) < 0)
    return -1;
  return addr;
}
```

在XV6中，sbrk的实现默认是eager allocation。这表示了，一旦调用了sbrk，内核会立即分配应用程序所需要的物理内存。但是实际上，对于应用程序来说很难预测自己需要多少内存，所以通常来说，应用程序倾向于申请多于自己所需要的内存。这意味着，进程的内存消耗会增加许多，但是有部分内存永远也不会被应用程序所使用到。

我们可以利用虚拟内存和page fault handler来实现lazy allocation。其核心思想就是调用sbrk时，只修改p->sz，但不分配实际的物理内存，等到应用程序真正使用到这个内存的时候就会触发page fault，这时候我们再分配物理内存并映射到page table中，然后再返回程序继续执行。

接下来老师简单讲述了如何修改sbrk，从而实现一个简单的lazy allocation，具体可见8.2。

# Zero Fill On Demand
当你查看一个用户程序的地址空间时，存在text区域，data区域，同时还有一个BSS区域（注，BSS区域包含了未被初始化或者初始化为0的全局或者静态变量）。

为什么要单独将这BSS区域列出来？这是因为我们可能定义一个很大的变量（例如开一个巨大的矩阵），但其中的值都是0，或者大多数时候用不了这么多空间。这个时候我们就可以通过page fault做一些优化。

通常可以调优的地方是，我有如此多的内容全是0的page，在物理内存中，我只需要分配一个page，这个page的内容全是0。然后将所有虚拟地址空间的全0的page都map到这一个物理page上。这样至少在程序启动的时候能节省大量的物理内存分配。见下图：
![[Pasted image 20230925191357.png]]

由于我们将所有未使用的空间都映射到同一个内容为0的物理内存，因而这个物理内存就是不能修改的。因而我们将这里的PTE都设置成只读的。直到程序用到了这些空间，就会触发page fault。

接下来在物理内存中申请一个新的内存page，将其内容设置为0，因为我们预期这个内存的内容为0。之后我们需要更新这个page的mapping关系，首先PTE要设置成可读可写，然后将其指向新的物理page。这里相当于更新了PTE，之后我们可以重新执行指令。见下图：
![[Pasted image 20230925191611.png]]

这种思想类似于Lazy Allocation，可以有两个好处：
1. 节省部分内存，直到申请的时候才分配。
2. exec需要做的工作变少。原来是需要给所有的变量都分配物理内存的，现在只需要全部映射到一个page就行。

# Copy On Write Fork
在我们未经修改的xv6中，shell处理执行时，会通过fork创建一个进程，将父进程全部拷贝到子进程中，然后子进程调用exec运行其他的程序，又抛弃了这个拷贝的空间。很显然这里有空间的浪费。

对于这个特定场景有一个非常有效的优化：当我们创建子进程时，与其创建，分配并拷贝内容到新的物理内存，其实我们可以直接共享父进程的物理内存page。所以这里，我们可以设置子进程的PTE指向父进程对应的物理内存page。为了确保隔离性，这里父进程与子进程的PTE标志位都需要设置成只读。
![[Pasted image 20230925192618.png]]

当子进程需要修改内存空间时，就会触发page fault，这时我们会分配一个新的物理内存page，然后将page fault相关的物理内存page拷贝到新分配的物理内存page中，并将新分配的物理内存page映射到子进程。

这时，新分配的物理内存page只对子进程的地址空间可见，所以我们可以将相应的PTE设置成可读写，并且我们可以重新执行store指令。实际上，对于触发刚刚page fault的物理page，因为现在只对父进程可见，相应的PTE对于父进程也变成可读写的了。
![[Pasted image 20230925192626.png]]

由于在进程视角触发page fault是因为向只读page中进行写入，因而内核必须要能够识别这是一个copy-on-write场景。下图是一个常见的多级page table，对于PTE的标志位，可以看到两位RSW。这两位保留给supervisor software使用，supervisor softeware指的就是内核。内核可以随意使用这两个bit位。所以可以做的一件事情就是，将bit8标识为当前是一个copy-on-write page。
![[Pasted image 20230925192949.png]]

接下来内容与copy-on-write lab有关：

现在出现了多个用户进程指向同一个物理内存page的情况，举个例子，当父进程退出时我们需要更加的小心，因为我们要判断是否能立即释放相应的物理page。

我们需要对于每一个物理内存page的引用进行计数，当我们释放虚拟page时，我们将物理内存page的引用数减1，如果引用数等于0，那么我们就能释放物理内存page。所以在copy-on-write lab中，你们需要引入一些额外的数据结构或者元数据信息来完成引用计数。
