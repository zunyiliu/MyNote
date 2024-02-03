# 目标
本实验要求我们打印出错行（在本次实验中是非法使用特权指令）的信息，包括：
- 出错文件路径
- 出错代码行
- 出错代码（源代码）

# 思路
## 获取文件代码信息
本次实验给我们提供了一个辅助函数，接口如下，可以将ELF文件中的.debug_line段翻译成三个数组信息，并保存在进程结构体中。
```c
void make_addr_line(elf_ctx *ctx, char *debug_line, uint64 length)
// make 3 arrays:  
// "process->dir" stores all directory paths of code files  
// "process->file" stores all code file names of code files and their directory path index of array "dir"  
// "process->line" stores all relationships map instruction addresses to code line numbers and their code file name index of array "file"
```

我们需要从ELF文件中读取.debug_line段，然后调用以上函数，从而获取文件代码信息。

## 读取.debug_line段
该函数需要我们自己实现，总的来说包含以下步骤：
1. 读取`Section header string table`
2. 读取`Section string table`，所有`section`的名字都在其中
3. 通过遍历比较找到`.debug_line`
4. 调用`make_addr_line`

## 打印出错信息
通过读取`mepc`寄存器，我们可以获取出错地址，然后就可以通过进程结构体中保存的信息找到出错位置，打印出错文件路径和出错代码行。

出错代码的打印比较复杂，这里我是通过答案才知道的：
1. 通过`spike_file_open()`函数打开源代码文件
2. 找到出错行
3. 打印出错行代码

