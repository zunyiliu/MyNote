中断对应的场景很简单，就是硬件想要得到操作系统的关注。例如网卡收到了一个packet，网卡会生成一个中断；用户通过键盘按下了一个按键，键盘会产生一个中断。操作系统需要做的是，保存当前的工作，处理中断，处理完成之后再恢复之前的工作。

很显然，中断、系统调用、page fault都是用的同一套trap机制。但中断也和系统调用有所不同：
1. asynchronous（异步）：当硬件生成中断时，Interrupt handler与当前运行的进程在CPU上没有任何关联。但如果是系统调用的话，系统调用发生在运行进程的context下。
2. concurrency（并发）：对于中断来说，CPU和生成中断的设备是并行的在运行。网卡自己独立的处理来自网络的packet，然后在某个时间点产生中断，但是同时，CPU也在运行。
3. program device（编程设备）：设备的编程包含了它有什么样的寄存器，它能执行什么样的操作，在读写控制寄存器的时候，设备会如何响应。

本节课我们会讨论：
- console中的提示符“$ ”是如何显示出来的
- 如果你在键盘输入“ls”，这些字符是怎么最终在console中显示出来的
- “$ ”是Shell程序的输出，而“ls”是用户通过键盘输入之后再显示出来的

# Interrupt硬件部分
我们主要关注外部设备的中断，外部设备映射到内核内存的某处，类似于读写内存，通过向相应的设备地址执行load/store指令，我们就可以对例如UART的设备进行编程。

所有的设备都连接到处理器上，处理器通过PLIC（Platform Level Interrupt Control）来管理外设的中断。其流程为：
- PLIC会通知当前有一个待处理的中断
- 其中一个CPU核会Claim接收中断，这样PLIC就不会把中断发给其他的CPU处理
- CPU核处理完中断之后，CPU会通知PLIC
- PLIC将不再保存中断的信息

# 设备驱动概述
我们今天要看的是UART设备的驱动，代码在uart.c文件中。

通常来说，管理设备的代码称为驱动，所有的驱动都在内核中。如果我们查看代码的结构，我们可以发现大部分驱动都分为两个部分，bottom/top。
- bottom：通常是Interrupt handler。当一个中断送到了CPU，并且CPU设置接收这个中断，CPU会调用相应的Interrupt handler。Interrupt handler并不运行在任何特定进程的context中，它只是处理中断。
- top：是用户进程，或者内核其他部分调用的接口。对于UART来说，这里有read/write接口，这些接口可以被更高层级的代码调用。

通常情况下，驱动中会有一些队列（或者说buffer），top部分的代码会从队列中读写数据，而Interrupt handler（bottom部分）同时也会向队列中读写数据。这里的队列可以将并行运行的设备和CPU解耦开来。
![[Pasted image 20231001145529.png]]

接下来我们看一下如何对设备进行编程。在SiFive的手册中，设备地址出现在物理地址的特定区间内，这个区间由主板制造商决定。操作系统需要知道这些设备位于物理地址空间的具体位置，然后再通过普通的load/store指令对这些地址进行编程。load/store指令实际上的工作就是读写设备的控制寄存器。这样就实现了操控设备。

# 在XV6中设置中断
当XV6启动时，Shell会输出提示符“$ ”，如果我们在键盘上输入ls，最终可以看到“$ ls”。我们接下来通过研究Console是如何显示出“$ ls”，来看一下设备中断是如何工作的。

对于“$ ”来说，实际上就是设备会将字符传输给UART的寄存器，UART之后会在发送完字符之后产生一个中断。在QEMU中，模拟的线路的另一端会有另一个UART芯片（模拟的），这个UART芯片连接到了虚拟的Console，它会进一步将“$ ”显示在console上。

对于“ls”，这是用户输入的字符。键盘连接到了UART的输入线路，当你在键盘上按下一个按键，UART芯片会将按键字符通过串口线发送到另一端的UART芯片。另一端的UART芯片先将数据bit合并成一个Byte，之后再产生一个中断，并告诉处理器说这里有一个来自于键盘的字符。之后Interrupt handler会处理来自于UART的字符。

RISC-V有许多与中断相关的寄存器：
- SIE（Supervisor Interrupt Enable）寄存器。这个寄存器中有一个bit（E）专门针对例如UART的外部设备的中断；有一个bit（S）专门针对软件中断，软件中断可能由一个CPU核触发给另一个CPU核；还有一个bit（T）专门针对定时器中断。我们这节课只关注外部设备的中断。
- SSTATUS（Supervisor Status）寄存器。这个寄存器中有一个bit来打开或者关闭中断。每一个CPU核都有独立的SIE和SSTATUS寄存器，除了通过SIE寄存器来单独控制特定的中断，还可以通过SSTATUS寄存器中的一个bit来控制所有的中断。
- SIP（Supervisor Interrupt Pending）寄存器。当发生中断时，处理器可以通过查看这个寄存器知道当前是什么类型的中断。
- SCAUSE寄存器，这个寄存器我们之前看过很多次。它会表明当前状态的原因是中断。
- STVEC寄存器，它会保存当trap，page fault或者中断发生时，CPU运行的用户程序的程序计数器，这样才能在稍后恢复程序的运行。

我们今天不会讨论SCAUSE和STVEC寄存器，因为在中断处理流程中，它们基本上与之前（注，lec06）的工作方式是一样的。接下来我们看看XV6是如何对其他寄存器进行编程，使得CPU处于一个能接受中断的状态。

1. 首先是位于start.c的start函数，这里将所有的中断都设置在Supervisor mode，然后设置SIE寄存器来接收External，软件和定时器中断，之后初始化定时器。
2. 之后main函数中调用consoleinit函数，其中又会调用uartinit。这个函数实际上就是配置好UART芯片使其可以被使用。这样原则上UART就可以生成中断了。但是因为我们还没有对PLIC编程，所以中断不能被CPU感知。
3. 在main函数中，我们需要调用plicinit函数。这里实际上就是设置PLIC会接收哪些中断，进而将中断路由到CPU。在XV6中，PLC接收UART的中断和IO磁盘的中断。
4. plicinit之后就是plicinithart函数。plicinit是由0号CPU运行，之后，每个CPU的核都需要调用plicinithart函数表明对于哪些外设中断感兴趣。每个CPU的核都表明自己对来自于UART和VIRTIO的中断感兴趣
5. 到目前为止，我们有了生成中断的外部设备，我们有了PLIC可以传递中断到单个的CPU。但是CPU自己还没有设置好接收中断，因为我们还没有设置好SSTATUS寄存器。在main函数的最后，程序调用了scheduler函数。
6. scheduler函数主要是运行进程。但是在实际运行进程之前，会执行intr_on函数来使得CPU能接收中断，intr_on函数只完成一件事情，就是设置SSTATUS寄存器，打开中断标志位。在这个时间点，中断被完全打开了。如果PLIC正好有pending的中断，那么这个CPU核会收到中断。

# UART驱动的top部分
接下来看如何从Shell程序输出提示符“$ ”到Console中。首先我们看init.c中的main函数，这是系统启动后运行的第一个进程。

这一部分感觉直接看翻译笔记比较好，讲的很详细：[笔记](https://mit-public-courses-cn-translatio.gitbook.io/mit6-s081/lec09-interrupts/9.5-uart-driver-top)

这里大致写一下过程：
1. init.c中创建console设备。并将0、1、2三个文件描述符都指向console
2. printf.c中调用write向文件描述符2写入，实际上就是向console写入
3. write在内核中就是sys_write，其又调用了filewrite。
4. 在filewrite函数中判断文件描述符类型，在这里属于设备，因而会调用设备对应的write函数，也就是consolewrite函数
5. 可以认为consolewrite是一个UART驱动的top部分。uart.c文件中的uartputc函数会实际的打印字符。
6. uartputc函数向buffer写入，然后调用uartstart函数。
7. uartstart就是通知设备执行操作。在某个时间点，我们会收到中断，然后就会进入UART的bottom部分。

# UART驱动的bottom部分
当产生中断时，PLIC会将该中断路由到一个特定的CPU核中，并且如果这个CPU核设置了SIE寄存器的E bit（注，针对外部中断的bit位），那么会发生以下事情：
- 首先，会清除SIE寄存器相应的bit，这样可以阻止CPU核被其他中断打扰，该CPU核可以专心处理当前中断。处理完成之后，可以再次恢复SIE寄存器相应的bit。
- 之后，会设置SEPC寄存器为当前的程序计数器。我们假设Shell正在用户空间运行，突然来了一个中断，那么当前Shell的程序计数器会被保存。
- 之后，要保存当前的mode。在我们的例子里面，因为当前运行的是Shell程序，所以会记录user mode。
- 再将mode设置为Supervisor mode。
- 最后将程序计数器的值设置成STVEC的值。

我们会进入trap机制，在usertrap函数中，调用devintr函数，再调用plic_claim函数来获取中断。这里CPU核就会认定这个中断。

接着又会调用uartintr和uartstart两个函数。

（说实话有点抽象，怎么绕来绕去的感觉，然后下面这段还挺清晰的）
![[Pasted image 20231001163536.png]]

# UART读取键盘输入
![[Pasted image 20231001164534.png]]

# Interrupt相关的并发
没太看明白，可以自己去看一看





