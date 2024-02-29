# Introduction
BurstFS也是一个burst buffer file system，并且采用聚集计算节点本地存储的方式。

Burst Buffer是一个处理突发I/O流量的强大硬件资源

目前还缺少管理Burst Buffer的软件，BurstFS就是为了解决这个问题

多进程同时写一个共享文件是一个问题，既要保证文件能够被正确写入，又要保证各进程能够定位到目标文件

多维数据集的写入和读出也通常不兼容，进程可能需要进行多次不连续的读操作才能获取需要的数据，一个合格的文件系统也应该要解决这个问题

BurstFS将写入本地突发缓冲区的数据的元数据组织到分布式键值存储中。为了应对上述I/O模式带来的挑战，BurstFS中设计了几种技术，包括可扩展元数据索引、同址I/O委托以及服务器端读取集群和管道。

综上所述，我们的研究做出了以下贡献：
- 我们设计并实现了一种突发缓冲区文件系统，以满足在领先的超级计算机上有效利用突发缓冲区的需要。
- 我们在BurstFS中引入了几种机制，包括用于快速定位共享文件的数据段的可扩展元数据索引，用于可扩展和可回收I/O管理的共定位I/O委托，以及用于支持快速访问多维数据集的服务器端集群和管道。
- 我们使用一组广泛的I/O内核和基准来评估BurstFS的性能。结果表明，BurstFS在并行写和读的聚合I/O带宽方面实现了线性可伸缩性。
- BurstFS是第一个临时性的burst buffer file system

# Background On I/O Patterns For Burst Buffer
分别提出了I/O模式和文件读取与写入不兼容的问题，两个问题都会导致性能下降。
![[Pasted image 20240229191924.png]]

![[Pasted image 20240229192145.png]]

# Ephemeral Burst Buffer File System
![[Pasted image 20240229194317.png]]
当在HPC系统上为批处理作业分配一组计算节点时，将使用本地附加的突发缓冲区(可能由内存、SSD或其他快速存储设备组成)在这些节点上动态构建BurstFS实例。

接下来，在这些节点的一部分上启动的一个或多个并行程序可以利用BurstFS向突发缓冲区写入数据或从突发缓冲区读取数据。

此外，同一作业分配中的并行程序可以共享同一个BurstFS实例上的数据和存储，这可以大大减少跨这些程序共享数据的后端持久文件系统的需求。

为了解决之前提出的问题，BurstFS设计了以下技术（如图3所示）：
- Scalable Metadata Indexing
- Co-locatd I/O Delegation
- Read Clustering and Pipelining

这三个技术的详解还是直接看论文吧，我也是直接略读过去的。