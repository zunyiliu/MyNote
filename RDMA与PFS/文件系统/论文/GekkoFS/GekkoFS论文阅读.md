# 推荐资源
- [burst buffer](https://blog.csdn.net/qq_31910613/article/details/128281735)
- [论文笔记](https://zhuanlan.zhihu.com/p/376758794)

# GekkoFS是什么
一个临时的，高度可扩展的**burst buffer file system**：
- a temporarily deployed, highly-scalable distributed file system
- node-local burst buffer file systems
- 针对HPC（High-Performance Computing）应用程序作了优化
- 提供大部分的POSIX标准

# Introduction
高性能计算已经从**传统的计算密集型**即（大规模的仿真应用等），转变为**数据驱动的以数据为中心**计算（基于大规模数据的生产，处理和分析等），这种转变或者新的方法可以解决之前无法解决的问题。**

数据驱动的工作负载给HPC的分布式文件系统带来了挑战：如大量的元数据操作，数据的同步，随机读写，小的IO请求等。这种存储访问模式和之前的HPC应用的大块顺序IO访问的模式有很大的区别。传统的并行文件系统不能很好的处理这种新模式的负载。

基于软件的解决方案：1）修改应用程序 2）引入新的存储中间件 3）或者引入high-level 程序库等。目前的这些方法都比较耗时，并且很难使用big data 或者 machine learning 的原有的软件库。

基于硬件的解决方法：1）增加SSD磁盘做为 burst buffer 或者使用本地的burst buffer 2）为了提高元数据的性能部署时引入dynamic burst buffer filesystem来解决。**关于burst buffer可以看这个[笔记](obsidian://open?vault=%E4%BB%8E%E5%A4%A7%E4%B8%89%E5%BC%80%E5%A7%8B%E7%9A%84%E5%AD%A6%E4%B9%A0&file=RDMA%E4%B8%8EPFS%2F%E6%96%87%E4%BB%B6%E7%B3%BB%E7%BB%9F%2F%E8%AE%BA%E6%96%87%2FGekkoFS%2FBurst%20Buffer)

和PFS相比，burst buffer filesystem 提高了系统的性能，而不用修改原有的应用程序，因此他们都实现了posix语义以适应大部分应用程序。然而POSIX的一些语义对大多数HPC应用很少或者基本没有用到，且这些语义会导致性能下降
>暗示GekkoFS是burst buffer FS，且只提供大部分的POSIX标准

GekkoFS是一个分布式的文件系统，有以下特点：
- 在用户态实现的分布式文件系统
- 聚集计算节点的本地高速存储资源（Burst Buffer的一种实现）
- 提供一个所有计算节点都可访问的全局命名空间
- 移除部分不必要的POSIX语义，保留大部分，从而提高性能
- 根据以往HPC的研究优化了部分操作
- 通过HPC RPC framework *Mercury*，将所有数据和元数据分布到所有计算节点，从而实现负载均衡
- 部署速度快，且性能高

# Related Work
GekkoFS可以分类为*node-local burst buffer* file systems，因为其使用计算节点本身的SSD来作为存储集群。

BurstFS与GekkoFS相似，但它是一个单机的burst buffer file system，并非分布式的。BeeOND是一个临时创建的分布式的burst buffer file system，但他提供完全的POSIX，因而在性能方面不如GekkoFS。

文件系统的元数据的性能瓶颈在于：**多个进程在同一个目录下创建大量文件时，POSIX语义会导致所有的操作都是串行化的**。GettkoFS 用一个key-value的存储系统来保存文件系统的元数据，用于提高元数据的性能。

# Design And Implementation
GekkoFS为某个计算任务提供一个用户空间的文件系统。它利用计算节点的本地存储（SSD）来分发数据和元数据，并将它们组织成单一的全局命名空间

GekkoFS应该有以下特性：
- 高可扩展：可以扩展到任意数量的计算节点
- 提供大部分的POSIX，既能保证文件系统基本操作，又不会造成性能损失
- 高兼容性：与存储硬件无关

## A. POSIX relaxation
GekkoFS提供了宽松的POSIX语义：
- 不支持分布式锁，因而应用程序需要保证不会有冲突发生
- 所有的元数据操作没有缓存，避免缓存一致性等复杂问题。
- 不支持rename和link操作，因为HPC应用中parallel job 很少用到这两个操作
- 不维护安全性，因为节点本地的文件系统已经有安全管理

## B. Architecture
GekkoFS架构包含两个主要部件：
- 客户端库
- 服务进程

客户端以库的形式提供给应用程序使用，它截获所有的GekkoFS操作调用，并将其转发给服务进程运行。服务进程即*GekkoFS daemon*，运行在所有计算节点上，接收到客户端的调用后进行处理，完成后将结果发送回客户端。

