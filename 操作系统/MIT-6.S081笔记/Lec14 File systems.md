说实话这一节的课程内容讲的不是很好，我觉得看教材+代码是比较好的方式。因而下面从教材+代码的角度进行笔记整理。

# 文件系统面对的挑战
- 文件系统需要磁盘上的数据结构来表示目录和文件名称树，记录保存每个文件内容的块的标识，以及记录磁盘的哪些区域是空闲的。
- 文件系统必须支持崩溃恢复（crash recovery）。也就是说，如果发生崩溃（例如，电源故障），文件系统必须在重新启动后仍能正常工作。风险在于崩溃可能会中断一系列更新，并使磁盘上的数据结构不一致（例如，一个块在某个文件中使用但同时仍被标记为空闲）。
- 不同的进程可能同时在文件系统上运行，因此文件系统代码必须协调以保持不变量。
- 访问磁盘的速度比访问内存慢几个数量级，因此文件系统必须保持常用块的内存缓存。

# 文件系统层次
|文件描述符（File descriptor）|
|---|
|路径名（Pathname）|
|目录（Directory）|
|索引结点（Inode）|
|日志（Logging）|
|缓冲区高速缓存（Buffer cache）|
|磁盘（Disk）|

xv6文件系统实现分为七层：
- 磁盘层读取和写入virtio硬盘上的块
- 缓冲区高速缓存层缓存磁盘块并同步对它们的访问
- 日志记录层负责保证崩溃时的恢复
- 索引节点为每个文件提供索引，并保存数据的指针
- 目录层将每个目录实现为一种特殊的索引结点，其内容是一系列目录项，每个目录项包含一个文件名和索引号
- 路径名层提供了分层路径名，并通过递归查找来解析它们
- 文件描述符层使用文件系统接口抽象了许多Unix资源

文件系统存储在磁盘上，磁盘只负责存储数据，因而文件系统要在磁盘上建立相应的数据结构。为此，xv6将磁盘划分为几个部分：
![[Pasted image 20231021101417.png]]
其中boot块存储引导扇区的数据，是操作系统启动时需要读取的数据。
super块为超级块，包含有关文件系统的元数据（文件系统大小（以块为单位）、数据块数、索引节点数和日志中的块数）。

# Buffer cache层
Buffer cache有两个任务：
1. 同步对磁盘块的访问，以确保磁盘块在内存中只有一个副本，并且一次只有一个内核线程使用该副本
2. 缓存常用块，以便不需要从慢速磁盘重新读取它们。代码在**bio.c**中。

## 缓冲区结构
其中dev表明这是哪个设备的存储块，blockno表明块号。refcnt表明正在使用该块的数量。data保存存储数据。
```C
struct buf {  
  int valid;   // has data been read from disk?  
  int disk;    // does disk "own" buf?  
  uint dev;  
  uint blockno;  
  struct sleeplock lock;  
  uint refcnt;  
  struct buf *prev; // LRU cache list  
  struct buf *next;  
  uchar data[BSIZE];  
};
```

bcache如下，这就是缓冲池，大小为NBUF，由一个lock负责整个缓冲池的锁。
```C
struct {  
  struct spinlock lock;  
  struct buf buf[NBUF];  
  
  // Linked list of all buffers, through prev/next.  
  // Sorted by how recently the buffer was used.  
  // head.next is most recent, head.prev is least.  
  struct buf head;  
} bcache;
```

## binit()
从缓冲池的初始化代码可以得知，`buf[NBUF]`是所有缓冲区的数组，实际上缓冲区的读取都需要从head中进行。这里head采用了双向链表的形式，将所有缓冲区串联在一起，后面我们将知道串联顺序是有讲究的。
```C
void  
binit(void)  
{  
  struct buf *b;  
  
  initlock(&bcache.lock, "bcache");  
  
  // Create linked list of buffers  
  bcache.head.prev = &bcache.head;  
  bcache.head.next = &bcache.head;  
  for(b = bcache.buf; b < bcache.buf+NBUF; b++){  
    b->next = bcache.head.next;  
    b->prev = &bcache.head;  
    initsleeplock(&b->lock, "buffer");  
    bcache.head.next->prev = b;  
    bcache.head.next = b;  
  }  
}
```

## bread()与bget()
```C
// If not found, allocate a buffer.  
// In either case, return locked buffer.  
static struct buf*  
bget(uint dev, uint blockno)  
{  
  struct buf *b;  
  
  acquire(&bcache.lock);  
  
  // Is the block already cached?  
  for(b = bcache.head.next; b != &bcache.head; b = b->next){  
    if(b->dev == dev && b->blockno == blockno){  
      b->refcnt++;  
      release(&bcache.lock);  
      acquiresleep(&b->lock);  
      return b;  
    }  
  }  
  
  // Not cached.  
  // Recycle the least recently used (LRU) unused buffer.  
  for(b = bcache.head.prev; b != &bcache.head; b = b->prev){  
    if(b->refcnt == 0) {  
      b->dev = dev;  
      b->blockno = blockno;  
      b->valid = 0;  
      b->refcnt = 1;  
      release(&bcache.lock);  
      acquiresleep(&b->lock);  
      return b;  
    }  
  }  
  panic("bget: no buffers");  
}  
  
// Return a locked buf with the contents of the indicated block.  
struct buf*  
bread(uint dev, uint blockno)  
{  
  struct buf *b;  
  
  b = bget(dev, blockno);  
  if(!b->valid) {  
    virtio_disk_rw(b, 0);  
    b->valid = 1;  
  }  
  return b;  
}
```
bread搭配bget使用，实际上就是从dev设备中读取块号为blockno的缓冲区。
- 如果缓冲池已经有该缓冲区了，就直接返回。
- 如果缓冲池没有该缓冲区，采用LRU算法替换一个缓冲区，并将b->valid置为0，从而重新从磁盘中进行读取。

这里LRU算法的使用是从双向链表的尾端开始查找，这是因为后面brelse()会将最近使用的缓冲区放在头部，这样相当于越靠近尾部的缓冲区最近就没有使用。

## brelse()
```C
// Release a locked buffer.  
// Move to the head of the most-recently-used list.  
void  
brelse(struct buf *b)  
{  
  if(!holdingsleep(&b->lock))  
    panic("brelse");  
  
  releasesleep(&b->lock);  
  
  acquire(&bcache.lock);  
  b->refcnt--;  
  if (b->refcnt == 0) {  
    // no one is waiting for it.  
    b->next->prev = b->prev;  
    b->prev->next = b->next;  
    b->next = bcache.head.next;  
    b->prev = &bcache.head;  
    bcache.head.next->prev = b;  
    bcache.head.next = b;  
  }  
    
  release(&bcache.lock);  
}
```
该函数负责释放缓冲区，如果缓冲区的refcnt减为0，就将其放在双向链表头部，表明是最近使用的。

# 块分配器
文件和目录内容存储在磁盘块中，磁盘块必须从空闲池中分配。xv6的块分配器在磁盘上维护一个空闲位图（bitmap），每一位代表一个块。0表示对应的块是空闲的；1表示它正在使用中。

## balloc()
```C
// Allocate a zeroed disk block.  
static uint  
balloc(uint dev)  
{  
  int b, bi, m;  
  struct buf *bp;  
  
  bp = 0;  
  //bitmap可能有多个块，一个块有1024字节，因而一个bitmap块有1024 * 8个位，也就能代表BPB个块的使用状态  
  for(b = 0; b < sb.size; b += BPB){ 
    bp = bread(dev, BBLOCK(b, sb)); //这里bp读取的就是bitmap块
    for(bi = 0; bi < BPB && b + bi < sb.size; bi++){  
      m = 1 << (bi % 8);  
      //这一部分可以不用完全看明白，实际上就是检查bitmap每一位对应的块是否空闲，空闲就可以分配  
      if((bp->data[bi/8] & m) == 0){  // Is block free?  
        bp->data[bi/8] |= m;  // Mark block in use.  
        log_write(bp);  
        brelse(bp);  
        bzero(dev, b + bi);  
        return b + bi;  
      }  
    }  
    //把获得的bitmap块释放  
    brelse(bp);  
  }  
  panic("balloc: out of blocks");  
}
```
反正就是这么个功能，用于找到一个空闲的块，并返回该块号。

# 索引节点层
inode分为磁盘上的inode和内存上的inode。磁盘上的inode是dinode。

磁盘上的inode都被打包到一个称为inode块的连续磁盘区域中。每个inode的大小都相同，因此在给定数字n的情况下，很容易在磁盘上找到第n个inode。
```C
struct dinode {  
  short type;           // File type  
  short major;          // Major device number (T_DEVICE only)  
  short minor;          // Minor device number (T_DEVICE only)  
  short nlink;          // Number of links to inode in file system  
  uint size;            // Size of file (bytes)  
  uint addrs[NDIRECT+1];   // Data block addresses->文件内容还是得存在data block中的，dinode负责索引  
};
```
- 字段`type`区分文件、目录和特殊文件
- 字段`nlink`统计引用此inode的目录条目数
- 字段`size`记录文件中内容的字节数
- `addrs`数组记录保存文件内容的磁盘块的块号。

