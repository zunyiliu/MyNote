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

接下来老师简单讲述了如何修改sbrk，从而实现一个


