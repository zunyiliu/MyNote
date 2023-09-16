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
2. 参考内核页表的初始化函数kvminit()，我们新建一个进程内核页表的初始化函数，实际上都是一样的操作。
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
3. 接着我们在allocproc()函数中调用我们的进程内核页表初始化函数
4. 将原本在procinit()函数中进行的内核栈映射搬到allocproc()函数中

**procinit()与allocproc()的区别**
一个是在boot阶段