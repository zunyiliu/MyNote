本任务需要我们实现一个并发的trie树，用于进行键值存储，具体可见项目文档。

# TrieNode类
## 类成员
```C++
protected:  
 /** Key character of this trie node */  
 char key_char_;  
 /** whether this node marks the end of a key */  
 bool is_end_{false};  
 /** A map of all child nodes of this trie node, which can be accessed by each  
  * child node's key char. */  
 std::unordered_map<char, std::unique_ptr<TrieNode>> children_;
```
其中key_char_表示该TrieNode的key。is_end_表示该node是否是一个key的末尾，只有TrieNodeWithValue类中该值才为true。children_用于表示所有子节点，用的是智能指针作为指引。

关于智能指针，请自行查阅资料。

## 构造函数
```C++
explicit TrieNode(char key_char) {  
  this->key_char_ = key_char;  
  this->is_end_ = false;  
  this->children_.clear();  
}

TrieNode(TrieNode &&other_trie_node) noexcept {  
  this->key_char_ = other_trie_node.GetKeyChar();  
  this->is_end_ = other_trie_node.IsEndNode();  
  this->children_ = std::move(other_trie_node.children_);  
}
```
关注一下这个移动构造函数，尤其是这个智能指针，必须要用std::move等工具进行所有权转让。

## 插入函数
```c++
std::unique_ptr<TrieNode> *InsertChildNode(char key_char, std::unique_ptr<TrieNode> &&child) {  
  if (HasChild(key_char) || key_char != child->GetKeyChar()) {  
    return nullptr;  
  }  
  this->children_[key_char] = std::move(child);  
  return &this->children_[key_char];  
}
```
这里使用了&&，代表右值引用，即不能直接作为赋值。剩余的按照函数要求写即可

# TrieNodeWithValue 类
```c++
template <typename T>  
class TrieNodeWithValue : public TrieNode {  
 private:  
  /* Value held by this trie node. */  
  T value_;
```
TrieNodeWithValue类是对TrieNode类的继承，新增了value_这个成员，表示最后节点的键值。

# Trie 类
```c++
class Trie {  
 private:  
  /* Root node of the trie */  
  std::unique_ptr<TrieNode> root_;  
  /* Read-write lock for the trie */  
  ReaderWriterLatch latch_;
```
Trie 类就是整个Trie数据结构的代表，这里包含一个TrieNode的根节点和一个读写锁。

## 插入函数
```C++
template <typename T>  
bool Insert(const std::string &key, T value) {  
  if (key.empty()) {  
    return false;  
  }  
  latch_.WLock();  
  std::unique_ptr<TrieNode> *pt = &root_;  
  for (uint64_t i = 0; i < key.size() - 1; i++) {  
    if (!(*pt)->HasChild(key[i])) {  
      pt = (*pt)->InsertChildNode(key[i], std::make_unique<TrieNode>(key[i]));  
    } else {  
      pt = (*pt)->GetChildNode(key[i]);  
    }  
  }  
  
  std::unique_ptr<TrieNode> *end_node = (*pt)->GetChildNode(key[key.size() - 1]);  
  if (end_node != nullptr && end_node->get()->IsEndNode()) {  
    latch_.WUnlock();  
    return false;  
  }  
  if (end_node != nullptr) {  
    auto new_node = new TrieNodeWithValue(std::move(**end_node), value);  
    end_node->reset(new_node);  
    latch_.WUnlock();  
    return true;  
  }  
  
  pt = (*pt)->InsertChildNode(key[key.size() - 1], std::make_unique<TrieNode>(key[key.size() - 1]));  
  auto new_node = new TrieNodeWithValue(std::move(**pt), value);  
  pt->reset(new_node);  
  latch_.WUnlock();  
  return true;  
}
```
1. 先查找到最后一个char字符的父节点
2. 判断子节点是否存在
	- 如果已经存在，且是TrieNodeWithValue节点，直接返回false
	- 如果已经存在，但不是TrieNodeWithValue节点，将其转化为TrieNodeWithValue节点
3. 子节点不存在，就直接创建

## 移除函数
```c++
bool Remove(const std::string &key) {  
  if (key.empty()) {  
    return false;  
  }  
  latch_.WLock();  
  std::stack<std::pair<char, std::unique_ptr<TrieNode> *>> s;  
  std::unique_ptr<TrieNode> *pt = &root_;  
  for (char i : key) {  
    if (!(*pt)->HasChild(i)) {  
      latch_.WUnlock();  
      return false;  
    }  
    s.push(make_pair(i, pt));  
    pt = (*pt)->GetChildNode(i);  
  }  
  
  while (!s.empty()) {  
    auto nkey = s.top().first;  
    auto node = s.top().second;  
    pt = (*node)->GetChildNode(nkey);  
    s.pop();  
    if (pt != nullptr && (*pt)->HasChildren()) {  
      continue;  
    }  
    (*node)->RemoveChildNode(nkey);  
  }  
  latch_.WUnlock();  
  return true;  
}
```
这里利用栈存储每个字符的父节点，然后依次判断能否递归删除。

