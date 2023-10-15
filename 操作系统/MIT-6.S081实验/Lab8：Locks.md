# Memory allocator
在初始的XV6中，所有CPU共享一个内存分配器，为减少不同CPU之间对于内存分配器锁的争用，我们需要做出以下改变：
1. 为每个CPU建立一个内存空闲页表。
2. 如果该CPU已经没有空闲页表可用，则需要“窃取”其他CPU的空闲页表。

(1)将`kmem`定义为一个数组，包含`NCPU`个元素，即每个CPU对应一个
```C
struct {
  struct spinlock lock;
  struct run *freelist;
} kmem[NCPU];
```

(2)修改`kfree`，将释放的页表放置在当前CPU对应的分配器中。注意调用`cpuid`前需要关闭cpu中断（根据提示）
```C
void  
kfree(void *pa)  
{  
  struct run *r;  
  
  if(((uint64)pa % PGSIZE) != 0 || (char*)pa < end || (uint64)pa >= PHYSTOP)  
    panic("kfree");  
  
  // Fill with junk to catch dangling refs.  
  memset(pa, 1, PGSIZE);  
  
  r = (struct run*)pa;  
  
  push_off();  
  int id = cpuid();  
  
  acquire(&kmem[id].lock);  
  r->next = kmem[id].freelist;  
  kmem[id].freelist = r;  
  release(&kmem[id].lock);  
  
  pop_off();  
}
```

(3)修改`kalloc`，使得在当前CPU的空闲列表没有可分配内存时窃取其他内存的。这里需要注意上锁顺序，在没有空闲页表时，先释放自己分配器的锁，然后按顺序获取锁查看有无空闲也表，这样就能防止死锁。
```C
void *  
kalloc(void)  
{  
  struct run *r;  
  push_off();  
  int id = cpuid();  
  
  acquire(&kmem[id].lock);  
  r = kmem[id].freelist;  
  if(r) {  
      kmem[id].freelist = r->next;  
      release(&kmem[id].lock);  
  }else{  
      //如果没有空闲页面，就得去窃取其他cpu的页面  
      release(&kmem[id].lock);  
      int i = 0;  
      for(;i < NCPU;i++){  
          if(i == id)  
              continue;  
          acquire(&kmem[i].lock);  
          if(kmem[i].freelist)  
              break;  
          release(&kmem[i].lock);  
      }  
      //此时i就是有空闲页面的CPU，并且还持有着锁  
      //这里也不用再获取自己的锁了，因为不会进行修改  
      if(i < NCPU) {  
          r = kmem[i].freelist;  
          kmem[i].freelist = r->next;  
          release(&kmem[i].lock);  
      }  
  }  
  
  if(r)  
    memset((char*)r, 5, PGSIZE); // fill with junk  
  
  pop_off();  
  return (void*)r;  
}
```

# Buffer cache
在初始的XV6中，所有cpu共享一个buffer分配器，我们需要改进从而减少锁争用。

(1)定义哈希桶结构，并在`bcache`中删除全局缓冲区链表，改为使用素数个散列桶
```C
#define NBUCKET 13
#define HASH(id) (id % NBUCKET)

struct hashbuf {
  struct buf head;       // 头节点
  struct spinlock lock;  // 锁
};

struct {
  struct buf buf[NBUF];
  struct hashbuf buckets[NBUCKET];  // 散列桶
} bcache;
```

(2)在`binit`中，（1）初始化散列桶的锁，（2）将所有散列桶的`head->prev`、`head->next`都指向自身表示为空，（3）将所有的缓冲区挂载到`bucket[0]`桶上。这部分与原有代码差不多。

(3)修改`brelse`，每次只对需要释放的块所在的散列桶进行上锁。
```C
void  
brelse(struct buf *b)  
{  
  if(!holdingsleep(&b->lock))  
    panic("brelse");  
  
  int bid = HASH(b->blockno);  
  
  releasesleep(&b->lock);  
  
  acquire(&bcache.buckets[bid].lock);  
  
  b->refcnt--;  
  
  acquire(&tickslock);  
  b->timestamp = ticks;  
  release(&tickslock);  
  
  release(&bcache.buckets[bid].lock);  
}
```

(4)修改`bget`，没有在当前散列桶找到缓冲区时，从其他桶寻找。这里需要注意两个问题：
1. 防止不同桶都在获取对方的锁，从而导致死锁。
2. 保证整个函数原子化，因而在没有找到缓冲区前不能释放当前桶的锁。
```C
// Not cached.  
// Recycle the least recently used (LRU) unused buffer.  
b = 0;  
for(int i = bid,cycle = 0;cycle != NBUCKET;i = (i + 1) % NBUCKET){  
    cycle++;  
    if(i != bid){  
        if(!holding(&bcache.buckets[i].lock))  
            acquire(&bcache.buckets[i].lock);  
        else  
            continue;  
    }  
    for(struct buf* tmp = bcache.buckets[i].head.next;tmp != 
		&bcache.buckets[i].head;tmp = tmp->next)  
        if(tmp->refcnt == 0 && (b == 0 || tmp->timestamp < b->timestamp))  
            b = tmp;  
    if(b){  
        // 如果是从其他散列桶窃取的，则将其以头插法插入到当前桶  
        if(i != bid) {  
            b->next->prev = b->prev;  
            b->prev->next = b->next;  
            release(&bcache.buckets[i].lock);  
  
            b->next = bcache.buckets[bid].head.next;  
            b->prev = &bcache.buckets[bid].head;  
            bcache.buckets[bid].head.next->prev = b;  
            bcache.buckets[bid].head.next = b;  
        }  
  
        b->dev = dev;  
        b->blockno = blockno;  
        b->valid = 0;  
        b->refcnt = 1;  
  
        acquire(&tickslock);  
        b->timestamp = ticks;  
        release(&tickslock);  
  
        release(&bcache.buckets[bid].lock);  
        acquiresleep(&b->lock);  
        return b;  
    }else{  
        if(i != bid)  
            release(&bcache.buckets[i].lock);  
    }  
}
```
我们在遍历桶时需要加上`!holding(&bcache.buckets[i].lock)`的判断，防止出现死锁。

其他部分代码都比较好理解。