# 线程切换中锁的限制
首先我们在线程切换也就是调用swtch()的过程中，要持有当前线程的锁。原因我们在Lec11中说过，就是保证线程完全切换到调度器线程后，才能释放这个锁，否则可能导致两个CPU核运行同一个线程。

第二，我们在线程切换的过程中，除了持有自己线程的锁以外，不能持有其他的锁，这更像是一个规则而不是代码中的限制（因为好像没有这方面的检查）。如果被切换的线程持有了一个文件锁，而切换到的线程需要使用该文件，就会尝试获取锁，然后因为陷入自旋，并产生死锁，因为在该线程结束以前，锁就不会被释放。

# Sleep&Wakeup 接口
我们可能希望线程之间需要有交互，这被称为Coordination。XV6中使用Sleep&Wakeup来实现。

在以下例子中，V函数作为生产者，P函数作为消费者。V函数每次使s->count+=1时，就会唤醒消费者进程。消费者进程在发现s->count!=0后就会进行“消费”。这就是一个Cooridination的例子。
```C
void V(struct semaphore* s) {
    acquire(&s->lock);
    s->count += 1;
    wakeup(s);
    release(&s->lock);
}

void P(struct semaphore* s) {
    acquire(&s->lock);

    while (s->count == 0)
        sleep(s, &s->lock);  // !pay attention
    s->count -= 1;
    release(&s->lock);
}
```

# Lost wakeup
接下来我们关注为什么上述的sleep函数中需要将锁作为参数传入。这是一个“丑陋”的实现，但却不得不这么做。

我们看以下例子，以下例子中我们不需要在sleep中传入锁的参数。但这会引发Lost wakeup。原因是，P进程运行到while(s->count == 0)与sleep(s)之间时，V进程调用了wakeup(s)，会发现没有需要唤醒的进程，也就不会产生作用。接着P进程就调用了sleep。倘若之后V进程不再调用V函数，那么P进程就永远不会被唤醒，这就是Lost wakeup的情况，可以理解为“丢失唤醒”。
```C
void V(struct semaphore* s) {
    acquire(&s->lock);
    s->count += 1;
    wakeup(s);  // !pay attention
    release(&s->lock);
}

void P(struct semaphore* s) {
    while (s->count == 0)
        sleep(s);  // !pay attention
    acquire(&s->lock);
    s->count -= 1;
    release(&s->lock);
}
```

# 如何避免Lost wakeup
有了以上现象，就可以解释为什么sleep函数需要传入锁参数了。

我们首先看XV6中wakeup的代码：
```C
// Wake up all processes sleeping on chan.
// Must be called without any p->lock.
void
wakeup(void *chan)
{
  struct proc *p;

  for(p = proc; p < &proc[NPROC]; p++) {
    acquire(&p->lock);
    if(p->state == SLEEPING && p->chan == chan) {
      p->state = RUNNABLE;
    }
    release(&p->lock);
  }
}
```
wakeup函数遍历所有线程，获取线程锁后查看p->state和p->chan，符合条件就会将p->state转为RUNNABLE，这样在调度器线程中，这个线程就会变为可见的，也就可以进行切换。

接着看XV中sleep的代码：
```C
// Atomically release lock and sleep on chan.
// Reacquires lock when awakened.
void
sleep(void *chan, struct spinlock *lk)
{
  struct proc *p = myproc();
  
  // Must acquire p->lock in order to
  // change p->state and then call sched.
  // Once we hold p->lock, we can be
  // guaranteed that we won't miss any wakeup
  // (wakeup locks p->lock),
  // so it's okay to release lk.
  if(lk != &p->lock){  //DOC: sleeplock0
    acquire(&p->lock);  //DOC: sleeplock1
    release(lk);
  }

  // Go to sleep.
  p->chan = chan;
  p->state = SLEEPING;

  sched();

  // Tidy up.
  p->chan = 0;

  // Reacquire original lock.
  if(lk != &p->lock){
    release(&p->lock);
    acquire(lk);
  }
}
```
调用sleep函数时会传入用来保护正在等待数据的锁。这样在该线程进入sleep之前，正在等待的数据就不会被修改。

接着sleep函数将数据锁换为线程锁，这样生产者线程就可以修改数据，但依旧无法wakeup该线程，因为他还持有线程锁。直到该线程调用sched()，切换到调度器线程后，线程锁才会被释放，这时wakeup就可以起作用了。

这里可以总结一些用锁规则：
- 调用sleep时需要持有condition lock，这样sleep函数才能知道相应的锁。
- sleep函数只有在获取到进程的锁p->lock之后，才能释放condition lock。
- wakeup需要同时持有两个锁才能查看进程。

# Pipe中的sleep和wakeup
每个管道都由一个`struct pipe`表示，其中包含一个锁`lock`和一个数据缓冲区`data`。字段`nread`和`nwrite`统计从缓冲区读取和写入缓冲区的总字节数。缓冲区是环形的：在`buf[PIPESIZE-1]`之后写入的下一个字节是`buf[0]`。而计数不是环形。此约定允许实现区分完整缓冲区（`nwrite==nread+PIPESIZE`）和空缓冲区（`nwrite==nread`），但这意味着对缓冲区的索引必须使用`buf[nread%PIPESIZE]`，而不仅仅是`buf[nread]`（对于`nwrite`也是如此）。

pipewrite代码如下：
```C
int
pipewrite(struct pipe *pi, uint64 addr, int n)
{
  int i;
  char ch;
  struct proc *pr = myproc();

  acquire(&pi->lock);
  for(i = 0; i < n; i++){
    while(pi->nwrite == pi->nread + PIPESIZE){  //DOC: pipewrite-full
      if(pi->readopen == 0 || pr->killed){
        release(&pi->lock);
        return -1;
      }
      wakeup(&pi->nread);
      sleep(&pi->nwrite, &pi->lock);
    }
    if(copyin(pr->pagetable, &ch, addr + i, 1) == -1)
      break;
    pi->data[pi->nwrite++ % PIPESIZE] = ch;
  }
  wakeup(&pi->nread);
  release(&pi->lock);
  return i;
}
```
当pipe的缓冲区满时（pi->nwrite == pi->nread + PIPESIZE），write进程就会唤醒read进程，并进入sleep。

此后就是不断从页表指定地址处将字符写入缓冲区。

piperead代码如下：
```C
int
piperead(struct pipe *pi, uint64 addr, int n)
{
  int i;
  struct proc *pr = myproc();
  char ch;

  acquire(&pi->lock);
  while(pi->nread == pi->nwrite && pi->writeopen){  //DOC: pipe-empty
    if(pr->killed){
      release(&pi->lock);
      return -1;
    }
    sleep(&pi->nread, &pi->lock); //DOC: piperead-sleep
  }
  for(i = 0; i < n; i++){  //DOC: piperead-copy
    if(pi->nread == pi->nwrite)
      break;
    ch = pi->data[pi->nread++ % PIPESIZE];
    if(copyout(pr->pagetable, addr + i, &ch, 1) == -1)
      break;
  }
  wakeup(&pi->nwrite);  //DOC: piperead-wakeup
  release(&pi->lock);
  return i;
}
```
当pipe缓冲区为空时（pi->nread == pi->nwrite），read进程就会进入sleep，等待write进程的唤醒。

之后read进程尽可能读取字符，直到缓冲区再次为空，此时i就是实际读取的字符数量。同时使用copyout将字符写入页表指定地址处。

# exit系统调用