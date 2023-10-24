# File system crash
我们举一个文件系统崩溃的例子，以下是创建文件的过程中，操作系统与磁盘block交互的过程：
![[Pasted image 20231024143302.png]]

从上面可以看出，创建一个文件涉及到了多个操作：
- 首先是分配inode，因为首先写的是block 33
- 之后inode被初始化，然后又写了一次block 33
- 之后是写block 46，是将文件x的inode编号写入到x所在目录的inode的data block中
- 之后是更新root inode，因为文件x创建在根目录，所以需要更新根目录的inode的size字段，以包含这里新创建的文件x
- 最后再次更新了文件x的inode

假设在以下位置发生电力故障或内核崩溃，因为内存数据保存在RAM中，所有的内存数据都丢失了，唯一能保留的只有磁盘上的数据。
![[Pasted image 20231024143409.png]]

在这个位置，我们先写了block 33表明inode已被使用，之后出现了电力故障，然后再次重启时，这个inode虽然被标记为已被分配，但是它并没有放到任何目录中，所以也就没有出现在任何目录中，因此我们也就没办法删除这个inode。

因而我们可以总结File System Crash的原因：多个写磁盘的操作没有通过原子的方式执行，即要么全部执行，要么都不执行。

# File system logging
XV6采用一种logging的日志恢复方式，这是一种来自数据库的解决方案。它有一些好的属性：
- 首先，它可以确保文件系统的系统调用是原子性的。比如你调用create/write系统调用，这些系统调用的效果是要么完全出现，要么完全不出现，这样就避免了一个系统调用只有部分写磁盘操作出现在磁盘上。
- 其次，它支持快速恢复（Fast Recovery）。在重启之后，我们不需要做大量的工作来修复文件系统，只需要非常小的工作量。
- 最后，原则上来说，它可以非常的高效，尽管我们在XV6中看到的实现不是很高效。

接下来我们将学习XV6如何实现这样一个logging系统。


首先还是回到XV6中的磁盘分布，可以看到在超级块后就是日志块。
![[Pasted image 20231021101417.png]]
在logging系统下，写磁盘将大致分为以下几个步骤：
1. `log_write`：将对磁盘的更新写入log磁盘块中
2. `commit`：将commit标志写入磁盘，这里我们成为commit point。从这一刻起，这个写磁盘的操作就是必须完成了。
3. `install log`：将log磁盘块中存储的更新写入对应的磁盘块中。
4. `clean log`：完成上一步后，将log块清除。

接下来我们考虑几个可能发生crash的位置：
1. 在第1步和第2步之间crash会发生什么？重启以后什么都不会做，就好像这个写磁盘操作从未发生。
2. 在第2步和第3步之间crash会发生什么？这时候log块已经全部写入，commit标志也已经写入，因而我们可以恢复写磁盘的所有内容，就好像写磁盘操作在crash之前就完成了。
3. 在第3步过程中和第4步之前这段时间crash会发生什么？在下次重启的时候，我们会redo log，我们或许会再次将log block中的数据再次拷贝到文件系统。这是可以接受的，因为重复写入并不会有什么问题。**当然在这个时间点，我们不能执行任何文件系统的系统调用。**

# XV6 logging 代码
## XV6 磁盘log结构
在上述提到的磁盘log区域中，首先是一个header block，内存代码如下：
```C
struct logheader {
  int n;               //代表有效的log block的数量
  int block[LOGSIZE];  //每个log block的实际对应的block编号
};
```

之后就是log块，存放了对应block更新的内容。整体结构如下图：
![[Pasted image 20231024145808.png]]

除了磁盘以外，内存中也有一个log的内存结构，代码如下：
```C
struct log {
  struct spinlock lock;
  int start;       // header block块号
  int size;        // 整体log大小
  int outstanding; // how many FS sys calls are executing.
  int committing;  // in commit(), please wait.
  int dev;
  struct logheader lh; //上述logheader结构，存储了每个log block实际对应的block编号
};
```

## 重启后的log系统恢复
```C
void
initlog(int dev, struct superblock *sb)
{
  if (sizeof(struct logheader) >= BSIZE)
    panic("initlog: too big logheader");

  initlock(&log.lock, "log");
  log.start = sb->logstart;
  log.size = sb->nlog;
  log.dev = dev;
  recover_from_log();
}
```
程序首先从super block中读取header block的块号、大小、设备，然后调用`recover_from_log()`

```C
// Read the log header from disk into the in-memory log header
static void
read_head(void)
{
  struct buf *buf = bread(log.dev, log.start);
  struct logheader *lh = (struct logheader *) (buf->data);
  int i;
  log.lh.n = lh->n;
  for (i = 0; i < log.lh.n; i++) {
    log.lh.block[i] = lh->block[i];
  }
  brelse(buf);
}

// Write in-memory log header to disk.
// This is the true point at which the
// current transaction commits.
static void
write_head(void)
{
  struct buf *buf = bread(log.dev, log.start);
  struct logheader *hb = (struct logheader *) (buf->data);
  int i;
  hb->n = log.lh.n;
  for (i = 0; i < log.lh.n; i++) {
    hb->block[i] = log.lh.block[i];
  }
  bwrite(buf);
  brelse(buf);
}

static void
recover_from_log(void)
{
  read_head();
  install_trans(1); // if committed, copy from log to disk
  log.lh.n = 0;
  write_head(); // clear the log
}
```
1. `recover_from_log`先读取header block，实际上里面存储的就是需要更新的块数与各log块对应的data block。
2. 调用`install_trans(1)`，代码如下，实际上就是将需要更新的块从log块更新到对应的data block中。可以看到这里遍历log块是直接以log.start为起始块号的，然后从log.lh.block[]中读取对应的data block，将两者进行memmove。
```C
// Copy committed blocks from log to their home location
static void
install_trans(int recovering)
{
  int tail;

  for (tail = 0; tail < log.lh.n; tail++) {
    struct buf *lbuf = bread(log.dev, log.start+tail+1); // read log block
    struct buf *dbuf = bread(log.dev, log.lh.block[tail]); // read dst
    memmove(dbuf->data, lbuf->data, BSIZE);  // copy block to dst
    bwrite(dbuf);  // write dst to disk
    if(recovering == 0)
      bunpin(dbuf);
    brelse(lbuf);
    brelse(dbuf);
  }
}
```
3. 接着`recover_from_log`将log.lh.n置为0，表示所有需要恢复的块都恢复完毕，然后调用`write_head`将头部再次写入。

这样我们就完成了恢复的所有流程，假如在这个过程中又发生了crash，也不会有问题，因为之后再重启时，XV6会再次调用initlog函数，无非就是重新install log一次，不会有问题。

恢复过程是不允许出现文件系统调用的，因而不用将log.committing置为1。

## log系统下文件系统调用的过程
### begin_op()
```C
// called at the start of each FS system call.
void
begin_op(void)
{
  acquire(&log.lock);
  while(1){
    if(log.committing){
      sleep(&log, &log.lock);
    } else if(log.lh.n + (log.outstanding+1)*MAXOPBLOCKS > LOGSIZE){
      // this op might exhaust log space; wait for commit.
      sleep(&log, &log.lock);
    } else {
      log.outstanding += 1;
      release(&log.lock);
      break;
    }
  }
}
```
这是文件系统调用前的函数，表示写入事务的开始：
1. 如果log正在commit过程中，那么就等到log提交完成，因为我们不能在install log的过程中写log
2. 如果写入log区域可能超出大小，也需要进入sleep等待之前的操作完成。
3. 如果当前操作可以继续执行，需要将log的outstanding字段加1（正在执行的系统调用数），最后再退出函数并执行文件系统操作。

### 