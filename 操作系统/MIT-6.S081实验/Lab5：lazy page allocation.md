这一节任务主题就是利用page fault处理实现lazy page allocation。主要就是在sbrk系统调用需要增加内存时，不立即分配内存，而是等待真正用到内容触发page fault的时候再进行分配。

我们首先在sbrk系统调用处进行修改：
```C
uint64  
sys_sbrk(void)  
{  
  int addr;  
  int n;  
  
  if(argint(0, &n) < 0)  
    return -1;  
  addr = myproc()->sz;  
  if(n >= 0)  
      myproc()->sz += n;  
  else if(myproc()->sz + n > 0)  
      myproc()->sz = uvmdealloc(myproc()->pagetable, myproc()->sz, myproc()->sz + n); 
  else  
      return -1;  
//  if(growproc(n) < 0)  
//    return -1;  
  return addr;  
}
```
将growproc()调用注释，需要增加内存时就仅仅修改p->sz，需要减少内存时就释放内存。

然后是usertrap函数：
```C
else if(r_scause() == 12 || r_scause() == 13 || r_scause() == 15){  
    uint64 faultAddr = r_stval();  
    char* mem;  
    if(faultAddr > PGROUNDUP(p->trapframe->sp) - 1 && faultAddr < p->sz && (mem = kalloc()) != 0){  
        memset(mem,0,PGSIZE);  
        if(mappages(p->pagetable, PGROUNDDOWN(faultAddr), PGSIZE, (uint64)mem, PTE_W|PTE_X|PTE_R|PTE_U) != 0){  
            kfree((void*)mem);  
            p->killed = 1;  
        }  
    }else{  
        p->killed = 1;  
    }
```
当trap类型是12、13、15（都是page fault）时，我们就进一步操作。先通过r_stval()读取出错的虚拟地址。然后确保以下三个条件：
- 如果某个进程在高于`sbrk()`分配的任何虚拟内存地址上出现页错误，则终止该进程。
- 正确处理内存不足：如果在页面错误处理程序中执行`kalloc()`失败，则终止当前进程。
- 处理用户栈下面的无效页面上发生的错误。

然后我们就可以将申请的物理内存映射到对应的虚拟地址上（用mappages()）

我们还要修改uvmcopy()和uvmummap()函数，将其中的panic进行注释，因为我们lazy allocation的情况下可能出现需要复制或需要取消映射的地址是根本没有分配的页面。
```C
if((pte = walk(pagetable, a, 0)) == 0)  
    continue;  
if((*pte & PTE_V) == 0)  
  continue;
```

最后我们要处理这样一种情况：进程从`sbrk()`向系统调用（如`read`或`write`）传递有效地址，但尚未分配该地址的内存。因而我们需要特殊处理，在这些系统调用使用到没有分配的内存时，直接进行分配。我们在argaddr()函数中进行处理：
```C
int  
argaddr(int n, uint64 *ip)  
{  
  *ip = argraw(n);  
  struct proc *p = myproc();  
  if(walkaddr(p->pagetable,*ip) == 0){//说明是空地址，那么就要分配  
      uint64 faultAddr = *ip;  
      char* mem;  
      if(faultAddr > PGROUNDUP(p->trapframe->sp) - 1 && faultAddr < p->sz && (mem = kalloc()) != 0){  
          memset(mem,0,PGSIZE);  
          if(mappages(p->pagetable, PGROUNDDOWN(faultAddr), PGSIZE, (uint64)mem, PTE_W|PTE_X|PTE_R|PTE_U) != 0){  
              kfree((void*)mem);  
              p->killed = 1;  
              return -1;  
          }  
      }else{  
          p->killed = 1;  
          return -1;  
      }  
  }  
  return 0;  
}
```

这样我们就完成了本次实验，还是比较简单的。