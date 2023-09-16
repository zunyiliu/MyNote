# Print a page table (easy)
这个任务要求我们实现一个打印给定页表三级映射的功能：
1. 模仿函数freeproc
2. 只有PTE_V的就是中间pte，还有PTE_R、PTE_X、PTE_W的就是叶子pte
3. 递归打印

# A kernel page table per process (hard)
这个任务要求我们为每个进程都建立一个内核页表，在此之前所有进程的内核态代码都是共用同一个内核页表，并且将自己的内核栈页表映射到该内核页表的不同区域，具体可见内核页表图：
![[Pasted image 20230912195523.png]]
可以看到再内核页表的上部有Kstack，这就是64个进程的内核栈映射区域，不同内核栈之间还有未映射的PTE作为隔离。

该任务具体操作如下：
1. 在proc结构体中新增一个字段作为内核页表的存储
```C
// Per-process state
struct proc {
  struct spinlock lock;

  // p->lock must be held when using these:
  enum procstate state;        // Process state
  struct proc *parent;         // Parent process
  void *chan;                  // If non-zero, sleeping on chan
  int killed;                  // If non-zero, have been killed
  int xstate;                  // Exit status to be returned to parent's wait
  int pid;                     // Process ID

  // these are private to the process, so p->lock need not be held.
  uint64 kstack;               // Virtual address of kernel stack
  uint64 sz;                   // Size of process memory (bytes)
  pagetable_t pagetable;       // User page table
  pagetable_t kernel_pageStable; //进程的内核页表
  struct trapframe *trapframe; // data page for trampoline.S
  struct context context;      // swtch() here to run process
  struct file *ofile[NOFILE];  // Open files
  struct inode *cwd;           // Current directory
  char name[16];               // Process name (debugging)
};
```
2. 参考内核页表的初始化函数`kvminit()`，我们新建一个进程内核页表的初始化函数，实际上都是一样的操作。
```C
pagetable_t
proc_kpt_init()
{
    pagetable_t pagetable = (pagetable_t) kalloc();
    if(pagetable == 0)
        return 0;
    memset(pagetable, 0, PGSIZE);

    // uart registers
    uvmmap(pagetable,UART0, UART0, PGSIZE, PTE_R | PTE_W);

    // virtio mmio disk interface
    uvmmap(pagetable,VIRTIO0, VIRTIO0, PGSIZE, PTE_R | PTE_W);

    // CLINT
    uvmmap(pagetable,CLINT, CLINT, 0x10000, PTE_R | PTE_W);

    // PLIC
    uvmmap(pagetable,PLIC, PLIC, 0x400000, PTE_R | PTE_W);

    // map kernel text executable and read-only.
    uvmmap(pagetable,KERNBASE, KERNBASE, (uint64)etext-KERNBASE, PTE_R | PTE_X);

    // map kernel data and the physical RAM we'll make use of.
    uvmmap(pagetable,(uint64)etext, (uint64)etext, PHYSTOP-(uint64)etext, PTE_R | PTE_W);

    // map the trampoline for trap entry/exit to
    // the highest virtual address in the kernel.
    uvmmap(pagetable,TRAMPOLINE, (uint64)trampoline, PGSIZE, PTE_R | PTE_X);

    return pagetable;
}
```
3. 接着我们在`allocproc()`函数中调用我们的进程内核页表初始化函数
4. 将原本在`procinit()`函数中进行的内核栈映射搬到`allocproc()`函数中

**procinit()与allocproc()的区别**
前者是在boot阶段进行，后者是分配空闲进程。

5. 在`scheduler()`函数中进行satp寄存器的切换，这是页表根地址的切换方式，这样我们就能在不同进程的内核页表中切换，执行完进程后，我们就得切换为全局内核页表。之后我们还需要调用`sfence_vma()`，这是用于清空TLB，也就是页表缓存。
6. 我们还需要在`freeproc`函数中添加进程内核页表的释放和内核栈的取消映射

至此我们就完成了这个任务。现在我们的进程都是使用自己的内核页表进行内核态的代码执行。事实上我们建立的进程内核页表就是全局内核页表的副本，因而我们还是无法实现内核态代码直接识别用户虚拟地址，还是需要先翻译成物理地址才能使用，下一个任务我们将解决这个问题。

# Simplify `copyin`/`copyinstr`（hard）
>内核的`copyin`函数读取用户指针指向的内存。它通过将用户指针转换为内核可以直接解引用的物理地址来实现这一点。这个转换是通过在软件中遍历进程页表来执行的。在本部分的实验中，您的工作是将用户空间的映射添加到每个进程的内核页表（上一节中创建），以允许`copyin`（和相关的字符串函数`copyinstr`）直接解引用用户指针。

这个实验的目的是，在进程的内核态页表中维护一个用户态页表映射的副本，这样使得内核态也可以对用户态传进来的指针（逻辑地址）进行解引用

首先我们要为映射程序内存做准备。实验中提示内核启动后，能够用于映射程序内存的地址范围是 \[0,PLIC)，我们将把进程程序内存映射到其内核页表的这个范围内，首先要确保这个范围没有和其他映射冲突。

查阅 xv6 book 可以看到，在 PLIC 之前还有一个 CLINT（核心本地中断器）的映射，该映射会与我们要 map 的程序内存冲突。查阅 xv6 book 的 Chapter 5 以及 start.c 可以知道 CLINT 仅在内核启动的时候需要使用到，而用户进程在内核态中的操作并不需要使用到该映射。

接下来的实验步骤如下：
1. 创建用户页表到内核页表的复制函数
```C
void
u2kvmcopy(pagetable_t pagetable,pagetable_t kernel_pagetable,uint64 start,uint64 sz)
{
    pte_t *pte_from,*pte_to;
    start = PGROUNDUP(start);
    for(uint64 i = start;i < sz;i += PGSIZE){
        if((pte_from = walk(pagetable,i,0)) == 0)
            panic("u2kvmcopy: pte_from does not exist");
        if((pte_to = walk(kernel_pagetable,i,1)) == 0)
            panic("u2kvmcopy: pte_to can not alloc");
        uint64 pa = PTE2PA(*pte_from);
        uint flag = PTE_FLAGS(*pte_from) & (~PTE_U);
        *pte_to = PA2PTE(pa) | flag;
    }
}
```
可以看到这个函数负责将地址从start开始，大小为sz的pagetable复制到kernel_pagetable的相同区域

2. 在每个修改进程用户页表的位置，都将相应的修改同步到进程内核页表中。一共要修改：fork()、exec()、growproc()、userinit()。其中，我们在growproc函数中添加防止进程空间过量的情况。
3. 替换copyin和copyinstr函数

这样我们就完成了该任务
