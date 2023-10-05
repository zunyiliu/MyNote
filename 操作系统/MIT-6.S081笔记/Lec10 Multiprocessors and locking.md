# race condition（竞态）
操作系统中存在这样的情况，即一个CPU读取数据结构，而另一个CPU正在更新它，甚至多个CPU同时更新相同的数据；如果不仔细设计，这种并行访问可能会产生不正确的结果或损坏数据结构。即使在单处理器上，内核也可能在许多线程之间切换CPU，导致它们的执行交错。

竞态条件是指多个进程读写某些共享数据（至少有一个访问是写入）的情况。

避免竞争的通常方法是使用锁，锁确保互斥。

# 锁如何避免race condition？
锁就是一个对象，就像其他在内核中的对象一样，有一个结构体叫做lock，它包含了一些字段，这些字段中维护了锁的状态。

锁有以下功能：
- 保护系统中的不变量。不变量是跨操作维护的数据结构的属性。操作可能暂时违反不变量，但必须在完成之前重新建立它们。这就需要在release之前完成。
- 实现串行化并发的临界区域。在锁保护的一段代码中，同时只有一个进程在执行。
- 限制性能。串行化必定会导致性能的下降。当有多个进程需要执行时，只有一个进程能执行，其他进程都需要等待。

锁有非常直观的API：
- acquire，接收指向lock的指针作为参数。acquire确保了在任何时间，只会有一个进程能够成功的获取锁。
- release，也接收指向lock的指针作为参数。release释放当前进程持有的锁，这样其他进程才能获取该锁。

锁的acquire和release之间的代码，通常被称为critical section。类似于关键区间，其原因如下：
- 在critical section中，系统以原子的方式执行共享数据的更新。即要么会一起执行，要么一条也不会执行。

# 什么时候使用锁？
一个非常保守同时也非常简单的规则是：
- 如果两个进程访问了一个共享的数据结构，并且其中一个进程会更新共享的数据结构，那么就需要对于这个共享的数据结构加锁。

#  锁的特性
锁的三个作用：
- 锁可以避免丢失更新。
- 锁可以打包多个操作，使它们具有原子性。
- 锁可以维护共享数据结构的不变性。

# 死锁
同一个进程的死锁例子：
- 一个进程首先acquire一个锁，然后进入到critical section；在critical section中，再acquire同一个锁；第二个acquire必须要等到第一个acquire状态被release了才能继续执行，但是不继续执行的话又走不到第一个release，所以程序就一直卡在这了。

多个进程的死锁例子：
- 假设xv6中的两个代码路径需要锁A和B，但是代码路径1按照先A后B的顺序获取锁，另一个路径按照先B后A的顺序获取锁。假设线程T1执行代码路径1并获取锁A，线程T2执行代码路径2并获取锁B。接下来T1将尝试获取锁B，T2将尝试获取锁A。两个获取都将无限期阻塞，因为在这两种情况下，另一个线程都持有所需的锁，并且不会释放它，直到它的获取返回。

解决死锁的方法就是对锁进行排序，多个进程都按同一顺序进行上锁，就能解决死锁的问题。

遵守全局死锁避免的顺序可能会出人意料地困难。有时锁顺序与逻辑程序结构相冲突，例如，也许代码模块M1调用模块M2，但是锁顺序要求在M1中的锁之前获取M2中的锁。有时锁的身份是事先不知道的，也许是因为必须持有一个锁才能发现下一个要获取的锁的身份。这种情况在文件系统中出现，因为它在路径名称中查找连续的组件。

# 自旋锁（Spin lock）的实现
自旋锁的实现解决了两个问题：
1. 同一时刻只有一个进程会获得锁
2. 防止编译器改变指令顺序

对于第一个问题，各个处理器都有特殊的硬件指令，这种指令保证原子性。对于xv6而言，这个特殊的指令就是amoswap（atomic memory swap）。这个指令接收3个参数，分别是address，寄存器r1，寄存器r2。这条指令会先锁定住address，然后把address的数据存到r2中，r1的数据写入address中。

接下来我们看一下如何使用这条指令来实现自旋锁。

我们先看acquire函数：
```C
// Acquire the lock.
// Loops (spins) until the lock is acquired.
void
acquire(struct spinlock *lk)
{
  push_off(); // disable interrupts to avoid deadlock.
  if(holding(lk))
    panic("acquire");

  // On RISC-V, sync_lock_test_and_set turns into an atomic swap:
  //   a5 = 1
  //   s1 = &lk->locked
  //   amoswap.w.aq a5, a5, (s1)
  while(__sync_lock_test_and_set(&lk->locked, 1) != 0)
    ;

  // Tell the C compiler and the processor to not move loads or stores
  // past this point, to ensure that the critical section's memory
  // references happen strictly after the lock is acquired.
  // On RISC-V, this emits a fence instruction.
  __sync_synchronize();

  // Record info about lock acquisition for holding() and debugging.
  lk->cpu = mycpu();
}
```

 `__sync_lock_test_and_set`函数是C标准库实现的原子操作，效果和上述硬件原子指令一样。在这个循环中，它不断将1与lock进行交换，如果lock中的数据是0，就说明获得了锁，且lock被置为1。如果lock中的数据是1，就说明锁已经被获取了，需要继续等待，同时lock中的数据仍然是1。

接下来我们看release函数：
```C
// Release the lock.
void
release(struct spinlock *lk)
{
  if(!holding(lk))
    panic("release");

  lk->cpu = 0;

  // Tell the C compiler and the CPU to not move loads or stores
  // past this point, to ensure that all the stores in the critical
  // section are visible to other CPUs before the lock is released,
  // and that loads in the critical section occur strictly before
  // the lock is released.
  // On RISC-V, this emits a fence instruction.
  __sync_synchronize();

  // Release the lock, equivalent to lk->locked = 0.
  // This code doesn't use a C assignment, since the C standard
  // implies that an assignment might be implemented with
  // multiple store instructions.
  // On RISC-V, sync_lock_release turns into an atomic swap:
  //   s1 = &lk->locked
  //   amoswap.w zero, zero, (s1)
  __sync_lock_release(&lk->locked);

  pop_off();
}
```
可以看到release函数中使用了`__sync_lock_release(&lk->locked)`函数，内部使用的也是atomic swap操作，将0写入到了lock中。保证了release也是一个原子操作。

这里我们注意到，acquire和release中都使用了`__sync_synchronize()`函数，该函数用于表示任何在它之前的load/store指令，都不能移动到它之后。这样我们就在acquire和release之间构建了一个界限，这个界限中的指令都不会被重排到critical section以外，这样就保证了锁的正确性。









