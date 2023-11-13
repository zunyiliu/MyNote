# 任务1-可扩展哈希表
## 可扩展哈希表原理
- Directory：存放Bucket指针的容器，可以动态生长，容器的每个元素通过哈希值进行索引
- Bucket：桶，用于存放Key/Value，大小可以自定义，在逻辑上相当于一个线性表
- Global Depth：Directory的深度。假设global depth为n，那么当前的directory必定有 $2^n$ 个entry。同时，给定一个key，需要取出这个key的低global depth位的二进制值，作为索引值，即`IndexOf(key)`函数。
- Local Depth：Bucket的深度。在当前的bucket之下，每个元素的key的低n位都是相同的。
![[Pasted image 20231113163508.png]]

拓展一下可知：
- 对于一个bucket来说，如果当前的global depth等于local depth，那说明这个bucket只有一个指针指向它。
- 如果当前的global depth大于local depth，必定不止一个指针指向它。
- 计算当前bucket有几个指针指向它的公式是$2^{GlobalDepth - LocalDepth}$ 

关键函数Insert思路如下：
1. 尝试插入Key，若插入成功，返回即可，若不成功，执行步骤2。
2. 判断当前`IndexOf(key)`指向的bucket下，该bucket是否满了。如果满了，执行步骤3。否则执行步骤7。
3. 如果当前global depth等于local depth，说明bucket已满，需要增长direcotry的大小。增加directory的global depth，并将新增加的entry链接到对应的bucket。否则，继续执行步骤4。
4. 记录当前的local mask，创建bucket1和bucket2，增加两个bucket的local depth，增加num bucket的数量。取出之前满了的bucket中的元素，按照local mask的标准将每个元素重新分配到bucket1和bucket2中。执行步骤5。
5. 对每个链接到产生overflow的bucket的direcotry entry，按照local mask的标准，重新分配指针指向。执行步骤6。
6. 重新计算`IndexOf(key)`，执行步骤2。
7. 插入指定的key/value pair。

在实现完这一套可扩展哈希表的机制后，就可以把这个数据结构看成是一个可以无限扩展的哈希表（不考虑收缩）

## Bucket操作
Bucket有三个操作函数：`Find()`、`Remove()`、`Insert()`。由于Bucket实际上就是一个线性表，因而都只需要线性遍历完成操作即可。注意按照头文件中的注释进行操作。

## ExtendibleHashTable操作
**Find操作**
```C++
auto ExtendibleHashTable<K, V>::Find(const K &key, V &value) -> bool {  
  latch_.lock();  
  int id = IndexOf(key);  
  auto pt = dir_[id];  
  bool flag = pt->Find(key, value);  
  latch_.unlock();  
  return flag;  
}
```
根据要求，我们需要通过IndexOf函数找到该key对应的directory中的下标，然后调用Bucket中的Find操作，在该bucket中查找该key。

**Remove操作**
操作和Find一样，只不过改为调用Bucket中的Remove操作。

**Insert操作**
```C++
void ExtendibleHashTable<K, V>::Insert(const K &key, const V &value) {  
  int id;  
  latch_.lock();  
  while (true) {  
    id = IndexOf(key);  
    if (!dir_[id]->IsFull()) {  
      break;  
    }  
    if (global_depth_ == GetLocalDepthInternal(id)) {  
      for (int i = 0; i < (1 << global_depth_); i++) {  
        auto tmp_pt = dir_[i];  
        dir_.push_back(tmp_pt);  
      }  
      global_depth_++;  
    }  
    id = IndexOf(key);  
    // 分裂bucket，并重新链接directory entry  
    RedistributeBucket(dir_[id]);  
  }  
  dir_[id]->Insert(key, value);  
  latch_.unlock();  
}
```
根据上述提供的思路，我们首先找到该key对应的directory中的下标，然后看对应的Bucket是否已满，如果未满就可以进行插入，否则就需要分裂Bucket，目的就是扩展每个Bucket的区分度，从而容纳下更多元素。

**RedistributeBucket操作**
```C++
auto ExtendibleHashTable<K, V>::RedistributeBucket(std::shared_ptr<Bucket> bucket) -> void {  
  num_buckets_++;  
  bucket->IncrementDepth();  
  int depth = bucket->GetDepth();  
  std::shared_ptr<Bucket> new_bucket(new Bucket(bucket_size_, depth));  
  int pre_mask = LowNNumber(std::hash<K>()(bucket->GetItems().begin()->first), depth - 1);  
  for (auto pt = bucket->GetItems().begin(); pt != bucket->GetItems().end();) {  
    int now_mask = LowNNumber(std::hash<K>()(pt->first), depth);  
    if (now_mask != pre_mask) {  // 说明要移到新的bucket中  
      new_bucket->Insert(pt->first, pt->second);  
      bucket->GetItems().erase(pt++);  
    } else {  
      pt++;  
    }  
  }  
  for (int i = 0; i < (1 << global_depth_); i++) {  
    if (LowNNumber(i, depth - 1) == pre_mask && LowNNumber(i, depth) != pre_mask) {  
      dir_[i] = new_bucket;  
    }  
  }  
}
```
这一步我们先找到这两个Bucket原来的低depth位，然后根据新的一位来区分每个元素，并将它们划分到两个Bucket中。

接着遍历Directory，将原来链接到该Bucket的dir重新判断并链接。

**易错点**
numBucket是目前创建的Bucket的数量，而不是Directory的大小，Directory的大小是$2^{GlobalDepth}$


# 任务2-LRU-K 替换策略
## 数据结构
```C++
size_t current_timestamp_{0};  
size_t curr_size_{0};  
size_t replacer_size_;  
size_t k_;  
std::mutex latch_;  
  
std::deque<size_t> *buf_;  
bool *st_;
```
- current_timestamp_：LRUKReplacer自带的时间戳，用整数表示
- curr_size_：LRUKReplacer的evictable frame的数量，初始为0
- repalcer_size_：LRUKReplacer的大小，填入的frame_id不能大于等于该大小
- k_：表示k的大小
- buf_：用于每个frame的记录
- st_：用于每个frame是否evictable的标记

## Evict操作
LRUK规则：
- 如果没有K次历史记录，直接使用inf
- 如果都有K次历史记录或都没有K次历史记录，就对比最早的历史记录，谁最早谁就替换

根据以上规则找到目前带有evictable标记中最应该被替换掉的frame

## RecordAccess操作
- 刷新当前时间戳，即current_timestamp_++
- 判断需要更新的frame的队列，如果大小为k，则先出队一个，在进行入队

## SetEvictable操作
- 如果该frame不存在，直接返回
- 如果set_evictable与frame状态有区别，更新current_timestamp_
- 更新st_

## Remove操作
- 如果该frame不存在，直接返回
- 清除st_记录
- 清除buf_记录
- curr_size_--

# 任务3-缓冲池管理器实例
## 数据结构
```C++
/** Number of pages in the buffer pool. */  
const size_t pool_size_;  
/** The next page id to be allocated  */  
std::atomic<page_id_t> next_page_id_ = 0;  
/** Bucket size for the extendible hash table */  
const size_t bucket_size_ = 4;  
  
/** Array of buffer pool pages. */  
Page *pages_;  
/** Pointer to the disk manager. */  
DiskManager *disk_manager_ __attribute__((__unused__));  
/** Pointer to the log manager. Please ignore this for P1. */  
LogManager *log_manager_ __attribute__((__unused__));  
/** Page table for keeping track of buffer pool pages. */  
ExtendibleHashTable<page_id_t, frame_id_t> *page_table_;  
/** Replacer to find unpinned pages for replacement. */  
LRUKReplacer *replacer_;  
/** List of free frames that don't have any pages on them. */  
std::list<frame_id_t> free_list_;  
/** This latch protects shared data structures. We recommend updating this comment to describe what it protects. */  
/*以上这些变量都需要保护*/  
std::mutex latch_;
```
- 一个缓冲区管理器包含了disk_manager、page_table_、replacer_、free_list_
- disk_manager用于写入和读出page
- page_table_ 用于标记page的在哪个frame
- replacer_ 用于LRUK替换策略

## NewPgImp操作
该函数用于在缓冲区中创建新的page
- 选出空闲的frame，如果没有空闲的frame，直接返回nullptr
- 若从replacer_中选取frame，需进行以下操作：
	- 调用Evict函数，驱逐一个frame
	- 若该frame对应的page 是脏页，需要写回磁盘