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

