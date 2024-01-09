常见的缩略语对照表如下，阅读的时候如果忘记了可以翻到前面查阅。
![](https://pic1.zhimg.com/80/v2-b6723caa5b291ee161d94fd8fd8ce09c_1440w.jpg)

# WQ
Work Queue简称WQ，是RDMA技术中最重要的概念之一。WQ是一个储存工作请求的队列，其中的元素就是WQE。

# WQE
WQE可以认为是一种“任务说明”，这个工作请求是软件下发给硬件的，这份说明中包含了软件所希望硬件去做的任务以及有关这个任务的详细信息。

比如，某一份任务是这样的：“我想把位于地址0x12345678的长度为10字节的数据发送给对面的节点”，硬件接到任务之后，就会通过DMA去内存中取数据，组装数据包，然后发送。

WQ这个队列总是由软件向其中增加WQE（入队），硬件从中取出WQE，这就是软件给硬件“下发任务”的过程，这个过程也称为POST。
![[Pasted image 20240109155824.png]]

# QP
Queue Pair简称QP，就是“一对”WQ的意思。

# SQ和RQ
WQ实际上是一个逻辑概念，SQ和RQ是WQ的实例。

任何通信过程都要有收发两端，QP就是一个发送工作队列和一个接受工作队列的组合，这两个队列分别称为SQ（Send Queue）和RQ（Receive Queue）。
![[Pasted image 20240109160134.png]]

需要注意的是，在RDMA技术中**通信的基本单元是QP**，而不是节点。如下图所示，对于每个节点来说，每个进程都可以使用若干个QP，而每个本地QP可以“关联”一个远端的QP。每个节点的每个QP都有一个唯一的编号，称为QPN（Queue Pair Number），通过QPN可以唯一确定一个节点上的QP。
![[Pasted image 20240109160412.png]]

# SRQ
Shared Receive Queue简称SRQ，意为共享接收队列。概念很好理解，就是一种几个QP共享同一个RQ时，我们称其为SRQ。以后我们会了解到，使用RQ的情况要远远小于使用SQ，而每个队列都是要消耗内存资源的。当我们需要使用大量的QP时，可以通过SRQ来节省内存。如下图所示，QP2~QP4一起使用同一个RQ：
![[Pasted image 20240109160506.png]]

# CQ
Completion Queue简称CQ，意为完成队列。其中的元素是CQE（Completion Queue Element）。

可以认为CQE跟WQE是相反的概念，如果WQE是软件下发给硬件的“任务书”的话，那么CQE就是硬件完成任务之后返回给软件的“任务报告”。
![[Pasted image 20240109160619.png]]

每个CQE都包含某个WQE的完成信息，他们的关系如下图所示：
![[Pasted image 20240109160639.png]]

# WR和WC
WR全称为Work Request，意为工作请求；WC全称Work Completion，意为工作完成。这两者其实是WQE和CQE在用户层的“映射”。因为APP是通过调用协议栈接口来完成RDMA通信的，WQE和CQE本身并不对用户可见，是驱动中的概念。用户真正通过API下发的是WR，收到的是WC。

WR/WC和WQE/CQE是相同的概念在不同层次的实体，他们都是“任务书”和“任务报告”。

# 总结
![[Pasted image 20240109160737.png]]
用户态的WR，由驱动转化成了WQE填写到了WQ中，WQ可以是负责发送的SQ，也可以是负责接收的RQ。硬件会从各个WQ中取出WQE，并根据WQE中的要求完成发送或者接收任务。任务完成后，会给这个任务生成一个CQE填写到CQ中。驱动会从CQ中取出CQE，并转换成WC返回给用户。

