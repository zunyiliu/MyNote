# Page Cache是什么
![[Pasted image 20240110110639.png]]
上图中，红色部分为 Page Cache。可见 Page Cache 的本质是由 Linux 内核管理的内存区域。我们通过 mmap 以及 buffered I/O 将文件读取到内存空间实际上都是读取到 Page Cache 中。

Page Cache包含Buffer Cache、Swap Cache。事实上Page Cache基本等同于Buffer Cache

# Page Cache的优势
**1.加快数据访问**
如果数据能够在内存中进行缓存，那么下一次访问就不需要通过磁盘 I/O 了，直接命中内存缓存即可。
由于内存访问比磁盘访问快很多，因此加快数据访问是 Page Cache 的一大优势。

**2.减少 I/O 次数，提高系统磁盘 I/O 吞吐量**
得益于 Page Cache 的缓存以及预读能力，而程序又往往符合局部性原理，因此通过一次 I/O 将多个 page 装入 Page Cache 能够减少磁盘 I/O 次数， 进而提高系统磁盘 I/O 吞吐量。

# Page Cache的劣势
1. 需要占用额外物理内存空间，物理内存在比较紧俏的时候可能会导致频繁的 swap 操作，最终导致系统的磁盘 I/O 负载的上升。
2. 对应用层并没有提供很好的管理 API，几乎是透明管理。应用层即使想优化 Page Cache 的使用策略也很难进行。因此一些应用选择在用户空间实现自己的 page 管理，而不使用 page cache，例如 MySQL InnoDB 存储引擎以 16KB 的页进行管理。
3. 在某些应用场景下比 Direct I/O 多一次磁盘读 I/O 以及磁盘写 I/O。

