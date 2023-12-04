在本次项目中，我们需要构建一个可以支持多线程并发的B+树，提供查找、插入、删除、叶节点遍历四个功能。
# B+ Tree Pages
## 概述
在本次项目中，B+树共有两种类型的page，分别是Internal Page和Leaf Page，分别对应内部节点和叶子节点。两种Page有相同之处，因而它们继承于Tree Page，共享一些操作。

三个Page分别对应三个文件：
- src/storage/page/b_plus_tree_page.cpp
- src/storage/page/b_plus_tree_internal_page.cpp
- src/storage/page/b_plus_tree_leaf_page.cpp

## 大小限制
- 根节点不受大小限制，如果根节点是内部节点类型，则大小至少为2，对应有两个儿子
- 内部节点大小最大为Max Size，最小为Max Size / 2上取整
- 叶子节点大小最大为Max Size - 1，最小为Max Size / 2下取整

# Search
## 概述
```C++
auto BPLUSTREE_TYPE::GetValue(const KeyType &key, std::vector<ValueType> *result, Transaction *transaction) -> bool
```
Search功能的入口函数如上，我们接收一个key，需要找到对应的value。如果找到就返回true，没找到就返回false。

大致流程如下：
1. 找到key所在的叶节点，并在从根节点到叶节点过程中遵循上锁原则（下面提到）
2. 在叶节点内部搜寻key，如果找到就可以返回value，否则就返回false

## Search的上锁原则
- 首先给root_page_id_latch上锁，保证根节点id不会发生变化
- 每次先获取儿子节点的RLatch，然后释放父节点的RULatch
- 最后返回的是一个带RLatch的叶子节点

## Search中的FindLeaf函数
1. 进入该函数时保证持有root_page_id_latch，这样才能确保从正确的根节点进入B+树
2. 获取根节点的page，并释放root_page_id_latch，获取page自身的latch
3. 只要节点本身不是叶节点，就一路向下
4. 需要调用内部节点的LookUp函数，找到key对应的下一个page_id
5. 找到叶子节点后，返回叶子节点的page

关于内部节点的LookUp函数：
![[Pasted image 20231204170349.png]]
1. 调用std::lower_bound函数，根据描述，我们构建一个Lambda函数，根据B+树提供的排序原则，找到第一个不满足该原则的key
>Returns an iterator pointing to the first element in the range `[`first`,` last`)` such that element < value (or comp(element, value)) is false, (i.e. that is greater than or equal to value), or last if no such element is found.
2. 如果target指向末尾，说明需要找最右边的value
3. 如果target指向的key正好满足，就直接找该value
4. 否则找target前一个的value

## Search中的GetValue函数
1. 调用FindLeaf找到key所在的叶子节点
2. 调用叶子节点的LookUp函数，找到key对应的value，也就是记录id
3. 释放叶子节点的RULatch，并从缓冲池中Unpin该page

关于叶子节点的LookUp函数：
![[Pasted image 20231204171346.png]]
与内部节点的LookUp函数原理差不多，利用std::lower_bound快速找到对应的value

