# 简介
![[Pasted image 20231211201431.png]]
我们已经实现了与Disk Manager交互的Buffer Pool Manager（project1）、建立在page上的Bplus Tree Index（project2），用于快速查找key对应的元组rid。

在整个bustub的架构中，SQL层不需要我们实现，bustub已经实现了大部分内容。我们可以在Optimizer处进行修改，但由于自身能力不足，无从下手修改。

因而本次project3聚焦于如果将整个规划树（Planner Tree）的每个Planner Node转化成对应的Executor，从而真正执行。

# SeqScan
`SeqScan`是`SeqScanPlanNode`的执行器，用于从对应table中扫描全部tuple并返回

**如何获取table**
1. plan中需要扫描的table_oid
2. 通过catalog（系统目录）可以找到对应的tableInfo及table_heap

**如何获取tuple**
通过table_heap可以获取该table的迭代器iterator

# Insert
`Insert`是`InsertPlanNode`的执行器。InsertPlanNode只有一个child，用于提供需要插入的tuple，同时提供需要插入的table_oid。除此以外，我们还需要更新建立在该table上的index

**关于table和index的区别**
table是直接存储在磁盘page上的，我们可以通过catalog直接获取每个table，并访问每个table上的tuple。

我们在project2中建立了BplusTreeIndex，这种索引可以帮助我们找到key和对应的value，通常来说就是列值和RID。

插入tuple是直接向page中进行插入，而我们的index是另一套系统，因而也就需要另外进行更新。

**如何获取indexes**
同样利用catalog，我们已经获取了对应的tableInfo，因而可以通过table_name找到table的所有index。

**如何更新index**
![[Pasted image 20231212165233.png]]
我们在向table_heap插入tuple后，即可更新index。我们需要遍历整个table_indexes，因为可能存在多个key-value关系，也就是在多个列上建立了index，每个都需要更新。

对于每种index，我们从tuple中提取出对应该index的key，value就是该元组的rid，然后进行插入即可。

**如何提取tuple的key**
可以看到tuple->KeyFromTuple需要table本身的schema、index的schema、index的建立的列。

深入该函数：
![[Pasted image 20231212165553.png]]
该函数遍历key_attrs的每一项，这里边存着该index建立的列的idx，从而我们可以调用GetValue来提取出tuple在该列的值，这就是为什么我们需要table本身的schema作为参数，因为我们需要将idx和列值一一对应。

最后我们需要重新组建key，也就是对应的tuple，这里涉及到tuple本身的构建函数，需要一个Value的数组和对应的schema，这里就是index本身的schema。

# Delete
`Delete`是`DeletePlanNode`的执行器。该`DeletePlanNode`只有一个child，用于提供需要删除的tuple，并提供需要删除的table_oid。

该执行器需要返回一个带有删除tuple数量的tuple。同时需要更新index

**如何删除tuple**
我们只需要调用TableHeap::MarkDelete函数，标记该tuple已经删除，实际的删除工作会在transaction commit阶段进行，这一部分将在project4中实现。

**如何更新index**
操作和Insert中的相同

**如何创建一个tuple**
这里我们需要返回删除tuple的数量，返回类型为tuple，其构造函数如下
![[Pasted image 20231212170936.png]]
我们需要传入一个Value的数组，用于表示该tuple有哪些值，其次我们需要传入一个schema，表示该tuple应该以什么形式呈现。

由于我们这里是返回的tuple，因而schema就是GetOutputSchema，value数组中也只有删除tuple数量一个值。

# IndexScan
`IndexScan`是`IndexScanPlanNode`的执行器，需要从对应index中找到元组rid，然后再从table中提取rid对应的tuple，按顺序进行输出。

**如何构建index iterator**
IndexScanPlanNode中提供了index_oid，我们通过这个从catalog中提取对应的indexInfo，然后将其转化为BPlusTreeIndexForOneIntegerColumn，**这一点在文档中有提到**

然后我们就可以直接获取该index的iterator

**如何从table_heap中提取tuple**
每个iterator都对应了一个rid，我们利用这个rid从对应的table_heap中调用GetTuple，从而找到对应的tuple进行返回。
![[Pasted image 20231212171757.png]]

