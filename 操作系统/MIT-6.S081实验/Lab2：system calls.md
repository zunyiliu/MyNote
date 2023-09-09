# 创建一个系统调用的方法
## User Space
- 在***Makefile***的**UPROGS**中添加需要的应用程序（不是系统调用）
- 将系统调用的原型添加到***user/user.h***
- 存根添加到***user/usys.pl***（看到就知道怎么写了）

完成以上工作后，我们就让用户空间相信内核中有这样一个系统调用可以使用，并且可以通过编译，但调用应用程序时会出现系统调用执行失败，这是因为我们还没有在内核中实现这个系统调用。
## Kernel Space
- 将系统调用编号添加到***kernel/syscall.h***
- 在***kernel/syscall.c***中添加上这个系统调用的实现函数以及对应编号
- 完成该系统调用的函数实现

完成以上工作后，我们就真的在内核中实现了一个系统调用。
## 其他
- 添加自己实现的辅助函数：需要在***kernel/defs.h***中声明定义
- 添加自己在内核中的文件：在***Makefile***的**OBJS**中添加自己的内核文件
# System call tracing
做完以上操作后，我们根据提示，在***kernel/sysproc.c***中添加一个`sys_trace()`函数

```C
uint64
sys_trace(void)
{
    int n;
    if(argint(0,&n) < 0)
        return -1;
    acquire(&tickslock);
    myproc()->traceId = n;
    release(&tickslock);
    return 0;
}
```

根据已有的系统调用函数模仿就行。我们需要在proc结构体中新建一个字段用于保存我们需要跟踪的系统调用号。

然后我们要在每次创建新分支时，将该字段一同复制。因而我们需要修改`fork()`（请参阅***kernel/proc.c***）将跟踪掩码从父进程复制到子进程。

然后我们就在***kernel/syscall.c***中的`syscall()`函数进行修改以打印跟踪输出。同时我们需要添加一个系统调用名称数组以建立索引。

```C
if(p->traceId && (p->traceId >> num) & 1) {
    printf("%d: syscall %s -> %d\n", p->pid,sys_name[num] , p->trapframe->a0);
```

# Sysinfo
首先在***kernel/kalloc.c***中添加一个函数，用于获取空闲内存量

```C
void freebyte(uint64 *cnt)
{
    *cnt = 0;
    struct run *r;
    acquire(&kmem.lock);
    r = kmem.freelist;
    while(r){
        r = r->next;
        *cnt += PGSIZE;
    }
    release(&kmem.lock);
}
```

然后再***kernel/proc.c***中添加一个函数，用于获取`state`字段不为`UNUSED`的进程数

```C
void procnum(uint64 *cnt)
{
    *cnt = 0;
    for(int i = 0;i < NPROC;i++)
        if(proc[i].state != UNUSED)
            (*cnt)++;
}
```

然后参阅`sys_fstat()`(**_kernel/sysfile.c_**)和`filestat()`(**_kernel/file.c_**)以获取如何使用`copyout()`执行此操作的示例，就可以开始写`sysinfo()`函数了。

```C
uint64
sys_sysinfo(void)
{
    struct sysinfo info;
    freebyte(&info.freemem);
    procnum(&info.nproc);

    uint64 addr;
    argaddr(0,&addr);

    if (copyout(myproc()->pagetable, addr, (char *)&info, sizeof info) < 0)
        return -1;

    return 0;
}
```






