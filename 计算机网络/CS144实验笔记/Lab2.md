# 序列号
我们现在回想一下TCP报文结构，可以知道，TCP序列号和确定号都是32位的无符号数字。而在我们之前实现的StreamReassembler中，我们用的试64位的无符号数字，这就说明了我们的TCP序列号是会重复使用的，因而序号建立32位无符号数字到64位无符号数字的对应关系。

同时我们需要知道TCP报文段中“开始和结束”都算作序列中的一个位置，但这在我们送入的数据中是不存在的，因而我们需要使用一个“绝对序列号”作为我们的中转，具体如下：
![[Pasted image 20230921203925.png]]
![[Pasted image 20230921203848.png]]
绝对序列号到流序列号的转换是容易的，只需要加减1就行。我们需要做的是序列号到绝对序列号的转换。我们会编写wrap()和unwrap()两个函数。

## wrap()
该函数将绝对序列号->序列号。
由于绝对序列号从0开始，因而我们可以通过将绝对序列号直接加到序列号上，然后模去周期即可。

## unwrap()
该函数将序列号->绝对序列号
由于绝对序列号从0开始，我们需要求得该序列号相对于起始序列号的偏移量，同时还要根据checkpoint找到最适合的绝对序列号。

# TCPReceiver
我们接收的是TCP报文段，由于TCP序号是随机的，我们需要将其首先转换到绝对序列号，然后通过之前写好的StreamReassembler函数将数据写入。

这里需要注意一点，无论TCP序号从哪里开始，绝对值序列号从0开始，流序列号也从0开始（不包括SYN和FIN）

我们先处理好该报文段的SYN和FIN标识符，把该初始化的初始化，然后根据任务给出的提示将接收窗口和序列长度设置好。

然后写入StreamReassembler要将序列号-1，这是绝对序列号到流序列号的转化。读出的时候则需要+1，这是流序列号到绝对序列号的转化。
```C
bool TCPReceiver::segment_received(const TCPSegment &seg) {  
    TCPHeader header = seg.header();  
    uint64_t index;  
    size_t seq_length = seg.length_in_sequence_space();  
    size_t win_size;  
    if(header.syn){  
        if(is_syn_set)//重复设置  
            return false;  
        is_syn_set = true;  
        is_isn_set = true;  
        isn = header.seqno;  
        index = 1;  
        checkpoint = 1;  
        abs_seq = 1;  
        seq_length--;  
        if(seq_length == 0)  
            return true;  
    }else if(!is_syn_set){  
        return false;  
    }else{  
        index = unwrap(header.seqno,isn,checkpoint);  
        checkpoint = index;  
    }  
    if(header.fin){  
        if(!is_syn_set)  
            return false;  
        is_syn_set = false;  
        seq_length--;  
    }  
    //设置接收窗口大小  
    win_size = window_size();  
    win_size = win_size ? win_size : 1;  
    //设置序列长度  
    seq_length = seq_length ? seq_length : 1;  
  
    //判断是否在窗口内  
    //序列：[index,index + seq_length)  
    //窗口：[abs_seq,abs_seq + win_size)  
    if(index >= abs_seq + win_size || abs_seq >= index + seq_length)  
        return false;  
    //推入序列  
    _reassembler.push_substring(seg.payload().copy(),index - 1,header.fin);  
    //更新abs_seq,这里+1是为了复原  
    abs_seq = _reassembler.get_index() + 1;  
    if(header.fin)  
        abs_seq += 1;  
    return true;  
}
```

说实话感觉还是有点难上手，我也不确定是自己没有理解好题目意思还是自己的动手能力不够强。感觉还是一开始太难理解了，理解能力不是很好，他又跟书上的TCP不太一样，没有那么理想化。就和之前TinyKv一样，不知道为什么要这么做，感觉还是理解能力不太够，之前TinyKv是不能理解代码，现在CS144和MIT6.S081是不能理解任务给出的概念。