# Backtrace(moderate)
编译器向每一个栈帧中放置一个帧指针（frame pointer）保存调用者帧指针的地址。你的`backtrace`应当使用这些帧指针来遍历栈，并在每个栈帧中打印保存的返回地址。

有关Stack Frame有两件事情是确定的：
- Return address总是会出现在Stack Frame的第一位
- 指向前一个Stack Frame的指针也会出现在栈中的固定位置

从下图我们可以知道，返回地址位于栈帧帧指针的固定偏移(-8)位置，并且保存的前一帧指针位于帧指针的固定偏移(-16)位置
![[Pasted image 20230925142838.png]]

XV6在内核中以页面对齐的地址为每个栈分配一个页面。因而我们在遍历栈的时候需要依靠`PGROUNDDOWN(fp)`和`PGROUNDUP(fp)`来确定是否遍历完栈。

# Alarm(Hard)
本任务中，我们需要添加一个新的`sigalarm(interval, handler)`系统调用，如果一个程序调用了`sigalarm(n, fn)`，那么每当程序消耗了CPU时间达到n个“滴答”，内核应当使应用程序函数`fn`被调用。

1. 首先我们需要按创建系统调用的流程走一遍
2. 然后我们需要在运行的进程中保存`interval`和`handler`，也就是在`struct proc`中新建字段，这样我们就能正确对比并调用。
3. 每一个滴答声，硬件时钟就会强制一个中断，这个中断在**kernel/trap.c**中的`usertrap()`中处理。

最重要的代码如下，我们需要在满足要求时调用handler函数，那么就在usertrap函数中将需要返回的地址进行替换，这样经过usertrapret和userret后，我们就会抵达处理函数。
```C
// give up the CPU if this is a timer interrupt.
if(which_dev == 2) {
    if(++p->ticks_count == p->alarm_interval) {
        // 更改陷阱帧中保留的程序计数器
        p->trapframe->epc = (uint64)p->alarm_handler;
        p->ticks_count = 0;
    }
    yield();
}
```

但是这样还不够，我们在完成处理函数后，还需要正确返回我们中断的地方。这就要求我们将整个trapframe保存下来，因为处理函数可能修改寄存器等。

所以我们在`struct proc`中新建一个trapframe的字段，然后在usertrap中进行保存，之后在`sigreturn`系统调用中将保存的trapframe副本进行替换，这样我们就恢复到了中断代码在trap中的情况，因而也就能正确返回。

```C
// give up the CPU if this is a timer interrupt.
if(which_dev == 2) {
  if(p->alarm_interval != 0 && ++p->ticks_count == p->alarm_interval && p->is_alarming == 0) {
    // 保存寄存器内容
    memmove(p->alarm_trapframe, p->trapframe, sizeof(struct trapframe));
    // 更改陷阱帧中保留的程序计数器，注意一定要在保存寄存器内容后再设置epc
    p->trapframe->epc = (uint64)p->alarm_handler;
    p->ticks_count = 0;
    p->is_alarming = 1;
  }
  yield();
}
```





