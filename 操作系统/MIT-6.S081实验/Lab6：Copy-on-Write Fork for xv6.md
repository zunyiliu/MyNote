本节实验依然是对page fault的应用。关于copy-on-write的策略已经在page fault的笔记中做了阐述。本节我们需要实现这个策略。

首先我们先在kalloc.c中新建一个物理页面的引用计数数组。这里我们仿造freelist，在新增一个计数数组的同时，也需要一个自旋锁。
```C
struct {  
    struct spinlock lock;  
    int cnt[PHYSTOP / PGSIZE];  
}ref;
```

其次我们修改kfree和kalloc。在kfree中，只有当物理页面的引用数减为0时，才真正释放，否则只用将引用数减一。在kalloc中，我们新建一个页面时要初始化引用数为1。
```C
void  
kfree(void *pa)  
{  
  struct run *r;  
  
  if(((uint64)pa % PGSIZE) != 0 || (char*)pa < end || (uint64)pa >= PHYSTOP)  
    panic("kfree");  
  
  acquire(&ref.lock);  
  if(--ref.cnt[(uint64)pa / PGSIZE] == 0) {  
      release(&ref.lock);  
      // Fill with junk to catch dangling refs.  
      memset(pa, 1, PGSIZE);  
  
      r = (struct run *) pa;  
  
      acquire(&kmem.lock);  
      r->next = kmem.freelist;  
      kmem.freelist = r;  
      release(&kmem.lock);  
  }else  
      release((&ref.lock));  
}  
void *  
kalloc(void)  
{  
  struct run *r;  
  
  acquire(&kmem.lock);  
  r = kmem.freelist;  
  if(r) {  
      acquire(&ref.lock);  
      ref.cnt[(uint64)r / PGSIZE] = 1;  
      kmem.freelist = r->next;  
      release(&ref.lock);  
  }  
  release(&kmem.lock);  
  
  if(r)  
    memset((char*)r, 5, PGSIZE); // fill with junk  
  return (void*)r;  
}
```

接下来我们定义四个辅助函数，功能如下，实现放在最后面：
- cowpage：判断一个页面是否为COW页面
- cowalloc：copy-on-write分配器
- krefcnt：获取内存的引用计数
- kaddrefcnt：增加内存的引用计数

接着我们修改uvmcopy函数，将父进程的物理页映射到子进程，而不是分配新页。在子进程和父进程的PTE中清除`PTE_W`标志，同时加上`PTE_F`标志。别忘了映射后需要将该物理页面的引用数加一。

接着我们修改usertrap函数，增加对页表错误的处理。这里先判断该出错的虚拟地址是否超过sz，然后判断该页面是否是COW页面，最后调用cowalloc分配一个页面。
```C
...
else if(r_scause() == 12 || r_scause() == 13 || r_scause() == 15){  
  uint64 fault_va = r_stval();  
  if(fault_va >= p->sz  
      || cowpage(p->pagetable,fault_va) != 0  
      || cowalloc(p->pagetable,PGROUNDDOWN(fault_va)) == 0){  
      p->killed = 1;  
  }
...
```

同时我们还要修改copyout，因为这里使用的物理页面可能是cow页面，就需要重新分配一个页面：
```C
if(cowpage(pagetable,va0) == 0){  
    pa0 = (uint64)cowalloc(pagetable,va0);  
}
```

最后放上cowalloc的实现代码：
```C
void* cowalloc(pagetable_t pagetable,uint64 va){  
    if(va % PGSIZE != 0)  
        return 0;  
  
    uint64 pa = walkaddr(pagetable, va);  // 获取对应的物理地址  
    if(pa == 0)  
        return 0;  
  
    pte_t* pte = walk(pagetable, va, 0);  // 获取对应的PTE  
  
    if(krefcnt((char*)pa) == 1){  
        //只有这一个引用，就直接修改PTE_W和PTE_F
        *pte |= PTE_W;  
        *pte &= ~PTE_F;  
        return (void*) pa;  
    }else{  
        char* mem = kalloc();  //新建一个引用数为1的页面
        if(mem == 0)  
            return 0;  
  
        memmove(mem,(char*)pa,PGSIZE);  //将旧页面复制到新页面
  
        *pte &= ~PTE_V;  //这里要先去掉PTE_V，因为mappages函数中会检查这一项。

        if(mappages(pagetable,va,PGSIZE,(uint64)mem, (PTE_FLAGS(*pte) | PTE_W) & ~PTE_F) != 0){  //将新建的页面映射到虚拟地址上
            kfree((char*)mem);  
            *pte |= PTE_V;  
            return 0;  
        }  
  
        kfree((char*)pa);  
        return mem;  
    }  
  
}
```