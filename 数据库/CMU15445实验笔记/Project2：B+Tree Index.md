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

# Insert
## 概述
```cpp
auto BPLUSTREE_TYPE::Insert(const KeyType &key, const ValueType &value, Transaction *transaction) -> bool
```
该接口提供key和value，需要在指定位置上进行插入，同时不允许重复键，如果插入失败就返回false

大致流程如下：
1. 如果为空树，需要创建一个B+树
2. 如果不是空树，就找到该key应该插入的叶子节点
3. 如果有重复键，就返回false
4. 如果叶子节点插入后未满，就直接返回true
5. 如果叶子节点满了，就需要分裂该叶子节点，并向上插入

## Insert的上锁原则
- 首先获取root_page_id_latch的WLatch
- 获取根节点的WLatch，并作如下判断
	- 如果根节点未满（叶子节点和内部节点要求不同），则可以释放root_page_id_latch，因为根节点不会发生变化
- 每次获取儿子page后，获取其WLatch，并判断其是否安全，如果安全，就释放之前所获取的全部祖先节点的WULatch。
	- 安全标准：假如该儿子节点发生Insert，仍然未满，就说明不会向上插入，也就说明是安全的。
- 最后返回叶子节点时，**保证所有可能发生改变的节点都持有WLatch，且page位于transaction中**

## ReleaseLatchFromQueue函数
这个函数保证释放所有在transaction中的page的WULatch，并调用`buffer_pool_manager_->UnpinPage`，这样就释放了在FindLeaf中取出的page

## Insert中的FindLeaf函数
根据Insert的上锁原则，不断向下，最终获取叶子节点。
- 最后返回时保证所有可能发生改变的祖先节点都持有WLatch并在transaction中。
- 返回的叶子节点保证获取WLatch，但不位于transaction中

## Insert中的Split函数
概述：
```cpp
INDEX_TEMPLATE_ARGUMENTS  
template <typename N>  
auto BPLUSTREE_TYPE::Split(N *node) -> N *
```
这里采用模板N，可以同时接收内部节点和叶子节点的split

大致流程：
1. 接收一个需要分裂的节点参数
2. 创建一个新page
3. 将该节点的后半部分数据移到新的page中，这里分为叶子节点的MoveHalfTo和内部节点的MoveHalfTo

关于叶子节点的MoveHalfTo：
1. 接收一个需要转移的目标节点参数
2. 设置自身节点大小为最小值
3. 将后半部分的数据直接转移到目标节点的尾部

关于内部节点的MoveHalfTo：
1. 接收一个需要转移的目标节点参数和BufferPoolManager
2. 设置自身节点大小为最小值
3. 将后半部分的数据转移到目标节点的尾部，并从BufferPoolManager中取出儿子节点，修改其父亲节点id。这里由于我们已经持有了该节点的Latch，所以我们可以直接修改儿子节点的信息

## Insert中的InsertIntoParent函数
- 该函数是一个递归函数
- 进入该函数时保证所有可能修改的祖先节点都已经上了WLatch，并保存在了transaction中。
- 我们需要一直向上插入，直到不会分裂为止
- 接收参数为old_node、new_node、需要向上插入的key、transaction

大致流程如下：
1. 判断old_node是否为根节点，根节点需要进行特殊处理，同时也是递归终止条件1
	- 创建新page
	- 将old_node和new_node分别设置为新page的儿子节点
	- 设置old_node和new_node的父亲节点id
	- 更新root_page_id，需要调用`UpdateRootPageId(0)`
	- 调用`ReleaseLatchFromQueue(transaction);`，释放所有祖先节点的WULatch
2. 根据old_node的parent_id找到父亲节点
3. 如果`parent_node->GetSize() < internal_max_size_`，那么说明插入后不需要分裂，这是递归中止条件2
	- 调用`InsertNodeAfter`函数
	- 调用`ReleaseLatchFromQueue`，释放所有祖先节点的WULatch
	- 调用`buffer_pool_manager_->UnpinPage`
4. 否则我们调用`InsertNodeAfter`函数后，将该parent_node进行split，一样的套路递归调用自身

代码如下：
![[Pasted image 20231205170651.png]]
每次递归调用后，我们都会调用`buffer_pool_manager_->UnpinPage`，这是因为`ReleaseLathFromQueue`保证释放所有写锁和之前FindLeaf中的获取的页，但这里需要保证设置这些改变的页为脏页

关于内部节点的InsertNodeAfter：
![[Pasted image 20231205171004.png]]
我们找到old_node在父节点中的位置，在他后面插入new_key和new_node的page_id

## Insert中的InsertIntoLeaf函数
该函数才是实际上的Insert函数，主要就是对以上辅助函数的组织和调用，流程就是上面的大致流程。

# Delete
## 概述
```cpp
void BPLUSTREE_TYPE::Remove(const KeyType &key, Transaction *transaction)
```
接收一个key，需要删除对应key的value

大致流程：
1. 找到叶子节点，并在叶子节点上进行删除
2. 如果删除后的叶子节点仍然满足大小要求，直接返回
3. 如果删除后的叶子节点不满足大小要求，进入`CoalesceOrRedistribute`函数，进行递归式的再分配或合并
4. 将transaction中需要删除的page全部删除

## Delete中的CoalesceOrRedistribute函数
- 这是一个递归函数，用于将传入的节点进行再分配或合并，从而使B+树满足要求
- 递归结束时，调用ReleaseLatchFromQueue，释放所有在FindLeaf中获取的锁和page

关于再分配：
- 再分配就是递归的终止条件，因为不再需要从父节点中删除key，也就不会发生改变
- 需要从当前节点的前一个兄弟节点或后一个兄弟节点中借一个key/value
- 完成借节点后还需要在父节点处修改对应的key

关于合并：
- 合并永远选择合并到前一个节点中
- 合并后需要从父节点中删除一个key
- 删除后需要递归调用CoalesceOrRedistribute函数，确保父节点满足要求

## Delete中的FindLeaf函数
和Insert的思路差不多，都是遵守安全的上锁原则，确保所有可能发生改变的节点都上了WLatch，且page位于transaction中

## Delete中的Coalesce函数
![[Pasted image 20231205185814.png]]
- 我们确保neighbor_node是最后合并的节点，因而我们需要将node的所有key转移到兄弟节点中
- 传入的index是node在parent中的index，这样就可以删除被移除节点在父节点中的key
- 由于父节点发生变化，需要递归调用CoalesceOrRedistribute函数，参数为parent_node

关于叶子节点的MoveAllTo函数
![[Pasted image 20231205190225.png]]
- 就是直接将所有key/value全部移到目标节点中
- 由于我们确保合并进前一个节点，因而可以直接设置目标节点的下一个兄弟节点指针
- 设置大小为0，表示删除

关于内部节点的MoveAllTo函数
![[Pasted image 20231205190353.png]]
- 接收的middle_key是被合并节点的第0个key（在parent中）
- 我们首先需要设备key\[0]，这样才能确保移交的key/value是正确的

## Delete中的Redistribute函数
![[Pasted image 20231205190626.png]]
- 叶子节点和内部节点的处理不同，因而需要分开处理
- 传入的from_prev表示邻居节点是否来自前一个，用于判断再分配函数

## Delete中的Remove函数
流程就是上述提到的大致流程

# Iterator
迭代器是位于叶子节点上的迭代器，具有迭代器的通用函数和操作，定义如下：
![[Pasted image 20231205191241.png]]
这里我们需要用到的变量包括：
- buffer_pool_manager_：用于存取page
- 当前所在的page和leaf
- 当前遍历到的key/value的index

## 构造函数
除了对应变量的初始化外，我们保证获取到的page是已经上了RLatch的

## 析构函数
不仅要释放当前的page，还要将page的锁释放

## operator++()
先将下一个兄弟节点上RLatch，然后释放当前page，并转移到下一个page

# Begin()、Begin(const KeyType &key)、End()
都比较好处理，可以直接看代码

