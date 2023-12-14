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

# Aggregation
AggregationPlanNode提供group-by columns和aggregation columns，我们需要依靠group-by columns将所有tuple进行分组，然后在每个分组中对每个aggregation columns进行聚合。

## 如何进行分组
系统提供了一个MakeAggregateKey函数和一个MakeAggregateValue的函数，都是接收一个tuple，然后返回一个std::vector\<Value> 

系统提供了一个SimpleAggregationHashTable的数据结构，可以简单理解为一个包含std::unordered_map与其他接口函数的哈希表。其key是AggregateKey，value是AggregateValue。

我们对每个tuple提取出AggregateKey和AggregateValue，然后将其插入哈希表，这样就实现了根据group-by columns进行分组

## 如何对aggregation columns进行聚合
我们将所有tuple插入哈希表的过程中，需要在每个分组中直接进行聚合计算。计算方式如下：
![[Pasted image 20231214164808.png]]
AggregateValue是一个vector数组，其中每一项就是需要进行聚合计算的值（Value）。对于每种聚合方式，有不同的计算方法：
- CountStarAggregate：即Count(\*)。需要计算所有列的数量，因而直接加1即可
- CountAggregate：即Count(column)，如果当前值不为Null，才能进行加1
- SumAggregate：即Sum(column)，如果当前值不为Null，就要计算列值的和
- MinAggregate：即Min(column)，如果当前值不为Null，计算最小值
- MaxAggregate：即Max(column)，如果当前值不为Null，计算最大值

## 如何处理聚合破坏迭代器模型的问题
聚合需要计算所有tuple后才能进行返回，这就违反了迭代器模型的Next规矩，因而我们需要在Init阶段就计算完所有的聚合结果，然后在Next阶段直接进行返回

## 如何返回
很显然我们需要对每个group-by的分组都计算聚合结果，然后分别返回。

根据文档所写：*The schema of aggregation is group-by columns, followed by aggregation columns.*\我们需要安排group-by的列在前，aggregate的列在后。返回方式如下：
![[Pasted image 20231214165634.png]]

# NestedLoopJoin
- NestedLoopJoinPlanNode有两个孩子节点分别提供外表和内表的tuple。
- 该项目只需要我们支持Left Join和Inner Join两种方式。
- NestedLoopJoinPlanNode有一个谓词负责判断两个元组是否能进行join

## 如何利用谓词判断是否能join
根据文档提示，我们需要调用谓词predicate的AbstractExpression::EvaluateJoin函数。该函数返回一个Value类型的值，可能是false、true和Null三种值，具体可以参考FilterExecutor如何利用。

根据提示，我们可以写出如下Match函数，用于判断两个tuple是否能join
![[Pasted image 20231214170450.png]]

## 如何匹配外表与内表
由于一个外表tuple可以匹配多个内表tuple，而Next函数每次只返回一个join结果，我们需要记录每次遍历的最后位置。

我们在Init函数中提前将外表和内表的tuple都存下来，然后给外表和内表都设置一个index，用于记录当前匹配的阶段：
- left_index：当前正在匹配的外表tuple
- right_index：下一个需要匹配的内表tuple

只要外表还有没匹配完的tuple，内表就需要继续匹配。内表匹配结束的标志是内表所有tuple都遍历了一遍。这样就需要将left_index++，进行下一个外表tuple的匹配。

关于Left Join：
Left Join保证保留所有外表tuple，因而如果没有匹配的内表tuple，就需要造一个空的tuple进行匹配。

## 如何返回结果
文档描述如下：
>The output schema of this operator is all columns from the left table followed by all the columns from the right table.

我们需要将外表的所有列先加入，然后再加入内表的所有列，返回形式如下：
![[Pasted image 20231214171347.png]]

# NestedIndexJoin
- 如果一个等值join，且其右表在等值条件上有索引，优化器Optimizer会生成一个NestedIndexJoinPlanNode。
- NestedIndexJoinPlanNode提供一个右表的索引和提供左表的Node，我们需要对每个左表tuple，构造对应index的probe key，然后去右表索引中找到匹配tuple的rid

## 如何构造probe key
根据index_->ScanKey的要求，我们需要一个tuple来从index中找到匹配的tuple的RID。构造方式如下：
![[Pasted image 20231214173028.png]]
- 我们首先从left_tuple中提取出join条件需要的Value
- 利用这个Value和索引本身的schema构造tuple，这就是key
- 调用index_info_->index_->ScanKey来找到对应的RID

## 关于匹配数量
根据文档所写，索引确保不会有重复的key-value对应情况。事实上这就是我们project2所写的内容，我们当时就确保了不会有重复的key值。

## 关于查找tuple
我们有了RID数组后，由于只可能匹配一个RID，因而我们直接取出RID，然后从table_heap中找到该tuple，然后就和NestedLoopJoin一样进行返回。



