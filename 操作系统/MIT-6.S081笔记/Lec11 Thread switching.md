# 线程概述
在XV6中，一个进程只能有一个线程，因而在这节课中，我们可以认定线程就是进程。但对于linux这样操作系统，一个进程可以拥有多个线程，这种时候就需要区分。

线程就是单个串行执行代码的单元，它只占用一个CPU并且以普通的方式一个接一个的执行指令。

今天我们要讲的多线程并行运行的策略就是：一个CPU在多个线程之间切换。

XV6中包含多种线程：
1. 用户线程：每个用户进程都包含一个线程，并有独立的内存空间。
2. 内核线程：每个用户进程都有一个内核线程负责执行内核态代码，所有的内核线程都共享内核内存（都用的同一个内核页面）
3. 调度线程：每个CPU都有一个调度线程，运行调度程序，之后会看到。

# XV6线程调度
在XV6中，一种线程调度的方式是定时器中断：每个CPU核上都有一个硬件设备，定时产生中断，从而用户进程会进入内核trap，然后调用yield()出让CPU，这里就实现了线程切换。

在执行线程调度的时候，操作系统需要能区分几类线程：
- 当前在CPU上运行的线程——RUNNING
- 一旦CPU有空闲时间就想要运行在CPU上的线程——RUNNABLE
- 以及不想运行在CPU上的线程，因为这些线程可能在等待I/O或者其他事件——SLEEPING

本节我们将讨论RUNNING与RUNABLE两类线程的切换。

# XV6线程切换
下面我们介绍从一个RUNNING线程切换到RUNNABLE线程的过程：
1. 定时器中断强迫线程从用户空间进程切换到内核，trampoline代码将用户寄存器保存trapframe中。
2. 执行yield()函数，并调用swtch()函数，将当前内核线程的寄存器（在cpu中）保存到proc->context中，并将调度器线程的寄存器加载到cpu中。这样我们就切换到调度器线程了。
3. 调度器线程在scheduler()中的swtch()返回，找到下一个RUNNABLE线程，再次执行swtch()函数，切换到对应线程。
4. 这样就完成了一个线程的切换。

# XV6线程切换代码
首先看一下proc结构体中的重要字段：
1. trapframe：保存了用户空间线程寄存器
2. context：保存了内核线程寄存器
3. kstack：保存了当前进程的内核栈
4. state：保存了当前进程状态
5. lock：该进程的锁

**定时器中断强迫用户进程进入内核**
```C
...
else if((which_dev = devintr()) != 0){
    // ok
...
// give up the CPU if this is a timer interrupt.
  if(which_dev == 2)
    yield();
...
```
usertrap()函数通过devintr()得知中断原因，随后根据which_dev 判断出定时器中断，就会调用yield()

**yield/sched函数**
```C
void
yield(void)
{
  struct proc *p = myproc();
  acquire(&p->lock);
  p->state = RUNNABLE;
  sched();
  release(&p->lock);
}
```
这里首先获取了进程的锁，然后修改进程状态为RUNNABLE。

这里获取锁的目的之一：即使我们将进程的状态改为了RUNABLE，其他的CPU核的调度器线程也不可能看到进程的状态为RUNABLE并尝试运行它。否则的话，进程就会在两个CPU核上运行了，而一个进程只有一个栈。

这里的锁会在之后释放，但不是在这个函数中的release释放。

```C
void
sched(void)
{
  int intena;
  struct proc *p = myproc();

  if(!holding(&p->lock))
    panic("sched p->lock");
  if(mycpu()->noff != 1)
    panic("sched locks");
  if(p->state == RUNNING)
    panic("sched running");
  if(intr_get())
    panic("sched interruptible");

  intena = mycpu()->intena;
  swtch(&p->context, &mycpu()->context);
  mycpu()->intena = intena;
}
```
sched()函数做了一系列的检查，这些我们都可以忽略。实际上这个函数就是调用了swtch()。

**swtch函数**
从上一节的sched()函数可知，swtch函数将当前的内核线程的寄存器保存到p->context中，然后将cpu调度线程寄存器加载到cpu寄存器中，这样就会恢复当前CPU核的调度器线程的寄存器，并继续执行当前CPU核的调度器线程。

swtch()内部实际上就是汇编语言编写的寄存器交换功能，不展开叙述。

这里我们首先关注一个重要的寄存器ra：
ra寄存器存储了该函数需要返回的地址，这就是为什么交换后寄存器后，从swtch函数会返回到scheduler中的swtch函数，因为调度器线程的ra就是这里。

接着我们关注为什么swtch()只交换了14个寄存器：
由于swtch是一个函数，我们实际上只用保存callee saved的寄存器，这就是14个。

最后我们关注sp寄存器：
sp寄存器指向当前进程的内核栈地址，从用户内核线程切换到调度器线程的过程中，sp寄存器也发生改变，这样才真正切换到调度器线程中。

**scheduler函数**
```C
void
scheduler(void)
{
  struct proc *p;
  struct cpu *c = mycpu();
  
  c->proc = 0;
  for(;;){
    // Avoid deadlock by ensuring that devices can interrupt.
    intr_on();
    
    int found = 0;
    for(p = proc; p < &proc[NPROC]; p++) {
      acquire(&p->lock);
      if(p->state == RUNNABLE) {
        // Switch to chosen process.  It is the process's job
        // to release its lock and then reacquire it
        // before jumping back to us.
        p->state = RUNNING;
        c->proc = p;
        swtch(&c->context, &p->context);

        // Process is done running for now.
        // It should have changed its p->state before coming back.
        c->proc = 0;

        found = 1;
      }
      release(&p->lock);
    }
    if(found == 0) {
      intr_on();
      asm volatile("wfi");
    }
  }
}
```
我们切换到调度器线程并从swtch函数返回后，实际上返回的是scheduler函数中的swtch，因为调度器线程每次就在这里调用swtch()。

之后就意味着刚刚执行的内核线程已经暂时执行完了，修改c->proc = 0，然后就会释放进程锁。没错，我们在内核线程中获得锁，最后在调度器线程中释放了锁。这样如果有其他CPU，那么那个CPU就可以获取刚刚放下的内核线程的锁，回到内核线程中的swtch()，然后释放锁。这就有点类似于一个交叉获得与释放锁的过程。

接着我们就可以寻找下一个RUNNABLE的线程，获得锁后进行swtch，这样就回到了那个被中断的线程。

**XV6线程第一次调用switch函数**
这一套调度流程看起来非常完美，但现在有一个问题，如何进入这个流程呢？

这一段可以直接看课程笔记，不在赘述。