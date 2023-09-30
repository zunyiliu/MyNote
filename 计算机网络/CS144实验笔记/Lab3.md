本实验需要我们完成TCP发送方部分，具体而言就是TCPSender

`TCPSender`将负责：
- 跟踪接收方的窗口（处理传入的确认号（**ackno**）和窗口大小（**window size**）） ；
- 尽可能通过读取`ByteStream`、创建新的TCP段（包括SYN和FIN标志，如果需要），填充窗口，并发送它们；
- 跟踪哪些段已经发送但尚未被接收方确认——我们称之为“未完成的”段；
- 如果发送后经过足够的时间但尚未确认，则重新发送未完成的段；

# fill_window
>`TCPSender`被要求填充窗口：它从其输入的`ByteStream`中读取并以`TCPSegments`的形式发送尽可能多的字节，只要窗口中有新的字节要读取和可用空间。你要确保你发送的每一个`TCPSegment`都能完全放入接收方的窗口中。使每个单独的`TCPSegment`尽可能大，但不能大于`TCPConfig::MAX_PAYLOAD_SIZE`（1452字节）所给的值。你可以使用`TCPSegment::length_in_sequence_space()`方法来计算一个段所占用的序列号的总数。你的TCPSender维护着一个名为`_next_seqn`的成员变量，它存储着从零开始的发送的绝对序列号。对于你发送的每一个段，你都要让`_next_seqno`增加段的长度，以便知道下一段的序列号。

首先我们确定一点，SYN和FIN都是要占一位的，因而我们添加这两个标志位时要考虑不超过接收窗口大小。SYN是一开始就会单独发的一个（联系TCP过程），因而不用考虑。FIN则需要保证先把数据发送完，再来考虑FIN。

关于接收窗口的计算：一方面是接受方给出的接收窗口大小，另一方面也要考虑已经发送但未确认的报文段，也就是`bytes_in_flight`，因而我们能发送的大小就是`size_t dataLen = min(_rwnd - bytes_in_flight(),TCPConfig::MAX_PAYLOAD_SIZE);`。这里必须取到最大，因为测试集都是按最大来取的。

代码如下。如果已经设置了syn，且stream中已经没有字符需要发送了，咱就直接return。接着就是正常的逻辑。
```C
void TCPSender::fill_window() {  
    if(is_syn_set && _stream.buffer_empty() && !_stream.input_ended())  
        return;  
    if(is_fin_set)  
        return;  
    size_t _rwnd = rwnd ? rwnd : 1;  
    size_t dataLen = min(_rwnd - bytes_in_flight(),TCPConfig::MAX_PAYLOAD_SIZE);  
    //判断窗口还有多少  
    if(dataLen <= 0)  
        return;  
  
    //通过函数得到TCPSegment  
    std::string str = _stream.peek_output(dataLen);  
    _stream.pop_output(dataLen);  
    TCPSegment segment = get_TCPSegment(str);  
    st.push_back(segment);  
  
    //更新_next_seqno  
    _next_seqno += segment.length_in_sequence_space();  
  
    //发送报文  
    _segments_out.push(segment);  
  
}
```

# ack_received
>从接收方收到一个确认信息，包括窗口的左边缘（= `ackno`）和右边缘（= `ackno + window size`）。`TCPSender`应该查看其未完成的段的集合，并删除任何现在已被完全确认的段（`ackno`大于该段中的所有序列号）。如果打开了新空间（指窗口变大），`TCPSender`可能需要再次填充窗口。如果`ackno`无效，即确认发送方尚未发送的数据，则此方法返回false。

这一节我们需要考虑的就是将已经被确认的报文段从缓存中去掉。同时如果接收窗口空出来了，我们就需要调用fill_window。代码如下：
```C
bool TCPSender::ack_received(const WrappingInt32 ackno, const uint16_t window_size) {  
    uint64_t abs_ackno = unwrap(ackno,_isn,_next_seqno);  
    //说明ackno无效  
    if(abs_ackno > _next_seqno)  
        return false;  
    //说明ackno更新了，需要重置计时器  
    if(abs_ackno > last_abs_ackno){  
        last_abs_ackno = abs_ackno;  
        rto = _initial_retransmission_timeout;  
        resend_cnt = 0;  
        timer.reset(rto);  
    }  
  
    std::list<TCPSegment> newst;  
    for(auto pt = st.begin();pt != st.end();pt++){  
        uint64_t leftno = unwrap(pt->header().seqno,_isn,_next_seqno);  
        uint64_t rightno = leftno += pt->length_in_sequence_space();  
        if(abs_ackno >= rightno)  
            continue;  
        newst.push_back(*pt);  
    }  
    st = newst;  
  
    //如果打开了新空间（指窗口变大），TCPSender可能需要再次填充窗口。  
    rwnd = window_size;  
    if(rwnd - bytes_in_flight())  
        fill_window();  
    return true;  
}
```

# tick
>经过的时间；`TCPSender`将检查重传计时器是否已过期，如果是，则以最低的序列号重传未发送的段。每隔几毫秒，你的`TCPSender`的`tick`方法就会被调用一次，它的参数是告诉你自上次调用该方法以来已经过了多少毫秒。

我们需要新建一个timer类来作为重传计时器，一方面记录重传间隔RTO，另一方面记录上一次调用的时间。如果超时，就需要进行重发，并作如下操作：
- (a) 重传TCP接收方尚未完全确认的最早（最低序列号）段。你需要在一些内部数据结构中存储未发送的段，以便能够做到这一点。
- (b) 如果窗口大小为非零：
	- i. 跟踪连续重新传输的次数，并增加它，因为你刚刚重新传输了一些内容。你的`TCPConnection`将使用这些信息来决定连接是否无望（连续重传次数过多）并需要中止。
	 - ii. 将RTO的值增加一倍。（这被称为“指数回退”——它会减慢糟糕网络上的重传速度，以避免进一步堵塞工作。我们将在稍后的课堂上了解更多有关这方面的内容。）
- (c) 启动重传timer，使其在RTO毫秒后过期（对于前一个要点中概述的加倍操作后的RTO值）。

因而代码如下：
```C
void TCPSender::tick(const size_t ms_since_last_tick) {  
    if(st.empty()){//空的就关闭计时器  
        timer.reset(rto);  
        return;  
    }  
    timer.update_time(ms_since_last_tick);  
    if(!timer.is_expired())  
        return;  
    TCPSegment resendSegment;  
    uint64_t min_reqno = 0xffffffffffffffff;  
    for(auto pt = st.begin();pt != st.end();pt++){  
        if(unwrap(pt->header().seqno,_isn,_next_seqno) < min_reqno) {  
            min_reqno = unwrap(pt->header().seqno, _isn, _next_seqno);  
            resendSegment = *pt;  
        }  
    }  
    resend_cnt += 1;  
    rto *= 2;  
    timer.reset(rto);  
    _segments_out.push(resendSegment);  
}
```

# send_empty_segment
>`TCPSender`应该生成并发送一个在序列空间中长度为零的`TCPSegment`，并将序列号正确设置为`_next_seqno`。如果所有者（你下周要实现的TCPConnection）想发送一个空的ACK段，这很有用。这种段（不携带数据，不占用序列号）不需要作为”未完成”来跟踪，也不会被重传。

这个函数很简单，就是之前的fill_window，但是不用传数据，只用传header。代码如下：
```C
void TCPSender::send_empty_segment() {  
    //生成一个序列空间长度为0的报文，只用填充头部  
    WrappingInt32 seqno = wrap(_next_seqno,_isn);  
    TCPHeader header;  
    header.seqno = seqno;  
    TCPSegment segment;  
    segment.header() = header;  
  
    //直接发送，不用记录  
    _segments_out.push(segment);  
}
```


到此我们的Lab3就完成了。


