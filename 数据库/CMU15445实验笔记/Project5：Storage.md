此篇为额外笔记，并非CMU15445 2022Fall实验内容。

# 概述
![[Pasted image 20231223193543.png]]
在bustub架构图中，storage层有一个非常重要的组件就是Table Heap，实际上这才是真正控制数据库表插入、删除的组件

# TableHeap
包含变量：
```cpp
private:  
 BufferPoolManager *buffer_pool_manager_;  
 LockManager *lock_manager_;  
 LogManager *log_manager_;  
 page_id_t first_page_id_{};
```
Table Heap是针对每一个table都有的一个单独组件，用于管理某一个table的所有page。Table Heap并不实际存储所有page，也不存储与page相关的元数据，关于page组织的元数据都存储在page本身。

bustub的table page组织为双向链表，Table Heap就负责通过table page上的元数据来管理整个table的存储内容。bustub通过遍历双向链表，获取每个page_id，然后向buffer_pool_manager获取实际的page。

first_page_id_是Table Heap非常重要的变量，负责存储该table的第一个page，相当于是双向链表的head。如果构造函数不包含first_page_id_的参数，就需要直接向buffer_pool_manager新建一个新的page。

Table Heap的所有功能都依赖于Table Page提供的api，因而我们需要弄清楚Table page的功能。

# TablePage
```cpp
/**  
 * Slotted page format:  
 *  ---------------------------------------------------------  
 *  | HEADER | ... FREE SPACE ... | ... INSERTED TUPLES ... |  
 *  ---------------------------------------------------------  
 *                                ^  
 *                                free space pointer  
 *  
 *  Header format (size in bytes):  
 *  ----------------------------------------------------------------------------  
 *  | PageId (4)| LSN (4)| PrevPageId (4)| NextPageId (4)| FreeSpacePointer(4) |  
 *  ----------------------------------------------------------------------------  
 *  ----------------------------------------------------------------  
 *  | TupleCount (4) | Tuple_1 offset (4) | Tuple_1 size (4) | ... |  
 *  ----------------------------------------------------------------  
 *  
 */
```
Table Page采用槽页式结构，最前面是Header，然后是每个tuple的slot，最后就是tuple的空间，tuple采用从后往前的插入方式。

Header中多种元数据，这些都包含在table page的4096字节当中。

每个tuple的slot中都包含offset和size两部分，用于标注偏移量和tuple大小。

## TablePage---InsertTuple
- 向前移动FreeSpacePointer，腾出新tuple的空间
- 将新tuple拷贝到指定空间
- 设置slot的offset和size
- 返回该tuple的rid，包含page id和slot id

# TablePage---MarkDelete
- 根据rid找到指定的slot
- 给tuple做上delete的标记

# TablePage---GetTuple
- 根据rid找到指定的slot
- 根据slot的offset找到指定区域，并将数据进行拷贝

# TablePage---UpdateTuple
- 根据rid找到指定的slot
- 将该tuple前的所有tuple继续前移，腾出位置
- 在新的tuple位置上进行拷贝

# Tuple
Tuple就是一行数据，存储方式就是上述的TablePage中的存储方式。

Tuple需要依靠一个Value数组和一个Schema来进行构造。Schema指定了这一行数据每一列的类型，Value数据指定了每一列的列值。

当前的bustub只支持`INT`和`VARCHAR`两种类型，它们都有基础固定长度，`VARCHAR`还有变长长度。对于定长类型，Tuple直接在Schema指定的列的offset上序列化数据。对于变长类型，Tuple在Schema指定的列的offset上存储指针，并将变长类型的实际数据存在Tuple最后端。

# Schema
Schema就是一行的存储形式，指明了一行有哪些列，每一列是什么类型。
