- [Project2](#project2)
	- [Raft算法](#raft算法)
		- [复制状态机](#复制状态机)
		- [Raft基础](#raft基础)
		- [领导人选举](#领导人选举)
		- [日志复制](#日志复制)
		- [安全性](#安全性)
		- [一些想法](#一些想法)
	- [Project2A](#project2a)
		- [RaftLog](#raftlog)
			- [RaftLog结构](#raftlog结构)
			- [RaftLog辅助函数](#raftlog辅助函数)
		- [Raft](#raft)
			- [Msg的收发与处理](#msg的收发与处理)
				- [MsgHup](#msghup)
				- [MsgRequestVote](#msgrequestvote)
				- [MsgRequestVoteResponse](#msgrequestvoteresponse)
				- [MsgPropose](#msgpropose)
				- [MsgAppend](#msgappend)
				- [MsgAppendResponse](#msgappendresponse)
				- [MsgBeat](#msgbeat)
				- [MsgHeartBeat](#msgheartbeat)
				- [MsgHeartBeatResponse](#msgheartbeatresponse)
			- [计时器Tick()](#计时器tick)
				- [Follower](#follower)
				- [Candidate](#candidate)
				- [Leader](#leader)
			- [节点状态变更](#节点状态变更)
			- [一些想法](#一些想法-1)
		- [RawNode](#rawnode)
			- [HasReady](#hasready)
			- [Advance](#advance)
	- [Project2B](#project2b)
		- [存储服务的读写流程](#存储服务的读写流程)
		- [proposeRaftCommand](#proposeraftcommand)
		- [HandleRaftReady](#handleraftready)
			- [SaveReadyState](#savereadystate)
			- [applyRequest](#applyrequest)
	- [Project2C](#project2c)
		- [触发流程](#触发流程)
		- [流程详解](#流程详解)

# Project2
在这个项目中，将实现一个基于raft的高可用kv服务器，这不仅需要实现 Raft 算法（Project2A），还需要实际使用它（Project2B），并为其提供日志压缩与快照应用功能（Project2C）。该项目有三个部分需要实现，包括：
* 实现基本的Raft算法
* 在 Raft 之上建立一个容错的KV服务
* 增加对 raftlog GC 和快照的支持
  
## Raft算法
Raft算法论文可参考[Raft算法论文中文翻译](https://github.com/maemual/raft-zh_cn/blob/master/raft-zh_cn.md)。此处是我对Raft算法的理解。

### 复制状态机
复制状态机是依靠一系列的日志进行指令应用的机器。在服务器集群中，一个服务器通过接收客户端发来的指令添加到自己的日志，又通过一致性模块与其他服务器进行通信从而保证其他服务器也拥有相同的日志序列，这样服务器集群就可以看作是一个高可靠的复制状态机。Raft算法就是一个一致性算法。

### Raft基础
在Raft中，一个服务器只可能处于三种状态之一：领导者(Leader)、跟随者(Follower)、候选人(Candidate)。一个服务器集群中只会有一个Leader，负责接收客户端发来的指令日志，并将这些日志同步到其他Follower上，进而实现日志的一致性。当Leader无法工作时，就会有Follower成为Candidate，进行竞选，进而成为新的Leader。三种状态的切换如下：
![](raft-图4.png)

### 领导人选举
Raft使用心跳机制来触发领导人选举，领导人每隔一段时间向跟随者发送心跳来维持自己的权威。一旦跟随者**选举超时**，它就会认为当前集群中没有领导人，就会触发选举。要开始选举，跟随者首先要转化为候选人，并自增任期，向各服务器发出请求投票的RPC。随后会有三种结果：
* 该节点当选领导人。节点当选领导人后会立即向各节点发出心跳（在TinyKv中是发送空的Entry）来维护自己的权威，并阻止其他节点继续发起选举。
* 其他节点当选领导人。节点在候选人状态下收到其他领导人发来的心跳或AppendEntry时，就要承认该领导人的合法地位，并回到跟随者状态。
* 没有节点当选领导人。为了避免这种情况，Raft算法采取了随机选举超时，从而让选票不会被瓜分。

### 日志复制
领导人从客户端接收日志，将该日志添加到自己的日志序列中，并赋予其索引号和任期。一个日志有唯一的索引和任期。接着领导人将日志复制到其他节点上，并保证大多数节点都已经同步该日之后，领导人就会选择提交该日志，进而就可以安全应用到状态机中。

这里还涉及到日志不一致的情况。论文中讲的比较详细，此处不再赘述。

### 安全性
* 选举限制：一个节点必须包含所有已提交的日志才能被选为领导人。这里Raft通过比较两个节点之间的日志谁比较新来决定是否进行投票，包括比较最后一条日志的任期和索引。我们可以这样理解，已经提交的日志是被同步到大多数节点上的，而一个节点要当选领导人就必须联系集群中的大多数节点，因而可以通过比较日志是否比较新来确定该节点是否拥有所有已提交的日志。
* 提交之前任期内的日志条目：对于当前任期之前任期提交的日志，并不通过判断是否已经在半数以上集群节点写入成功来作为能否提交的依据。只有当前leader任期内的日志是通过比较写入数量是否超过半数来决定是否可以提交的。对于任期之前的日志，Raft采用的方式，是只要提交成功了当前任期的日志，那么在日志之前的日志就认为提交成功了。

### 一些想法
* 5 个服务器节点是一个典型的Raft集群，这允许整个系统容忍 2 个节点失效。这是因为集群保证大多数节点拥有已经提交的日志，因而如果有两个节点失败，也能保证有一个节点拥有已经提交的所有日志，进而能够继续工作。

## Project2A
本节要实现的就是整个Raft层，包括RaftLog模块、Raft模块、RawNode模块，分别在log.go、raft.go、rawnode.go中。三者的关系如下：
* RaftLog为Raft节点在内存中的存储模块，管理所有未被截断的日志，并维护committed、applied、stabled三种指针。保存待应用的快照。
* Raft为Raft节点的具体形式，需要进行Raft节点的消息处理，进行节点状态的转变。
* RawNode为Raft节点与上层的联系模块，用来接收上层传来的信息，将信息下传给 Raft 模块。同时还提供一些操作接口供上层使用。

三者的关系可用下图表示(注：此图非本人创作)
![](raft关系图.png)

### RaftLog
该模块主要在log.go文件中。

#### RaftLog结构
我们首先看RaftLog对日志的组织形式。RaftLog主要是在内存中保存未截断的日志，或是上一次快照应用后的日志，全部保存在log entries中。同时需要维护几个指针用于标识日志的状态。这里首先要知道一点是，日志索引与日志在entries中的索引是不一样的。日志索引为日志添加到entries中赋予的索引号，由于entries可能不断发生压缩截断，因而索引号和entries的索引不是一个东西。知道这一点后我们继续往下看，first标志目前entries中第一个日志的索引号，applied标志已经应用的日志的索引号，committed标志已经提交（同步到多数节点）的日志的索引号，stabled标志已经持久化即落盘的日志的索引号，last标志目前entries中最后一个日志的索引号。

```GO
// RaftLog manage the log entries, its struct look like:
//
//	snapshot/first.....applied....committed....stabled.....last
//	--------|------------------------------------------------|
//	                          log entries
// for simplify the RaftLog implement should manage all log entries
// that not truncated
// 为了简化RaftLog的实现，应该管理所有未被截断的日志条目。
type RaftLog struct {
	// storage contains all stable entries since the last snapshot.
	//storage包含自上次快照以来的所有稳定条目。
	storage Storage

	// committed is the highest log position that is known to be in
	// stable storage on a quorum of nodes.
	//committed是已知的在一个法定人数的节点上稳定存储的最高日志位置。
	committed uint64

	// applied is the highest log position that the application has
	// been instructed to apply to its state machine.
	// applied是指应用程序被指示应用于其状态机的最高日志位置。
	// Invariant: applied <= committed
	applied uint64

	// log entries with index <= stabled are persisted to storage.
	// It is used to record the logs that are not persisted by storage yet.
	//索引<= stabled的日志条目被持久化到存储。它被用来记录那些还没有被存储持久化的日志。
	// Everytime handling `Ready`, the unstabled logs will be included.
	stabled uint64

	// all entries that have not yet compact.
	//所有尚未压缩的条目。
	entries []pb.Entry

	// the incoming unstable snapshot, if any.
	// (Used in 2C)
	pendingSnapshot *pb.Snapshot

	// Your Data Here (2A).
	FirstIndex uint64
}
```


这里我们先给出RaftLog的创建函数，并接着说明各指针与storage的关系：
```GO
// newLog returns log using the given storage. It recovers the log
// to the state that it just commits and applies the latest snapshot.
// newLog返回使用给定storage的日志。它将日志恢复到刚刚提交并应用最新快照的状态。
func newLog(storage Storage) *RaftLog {
	// Your Code Here (2A).
	hardState, _, _ := storage.InitialState()
	commit := hardState.Commit
	firstindex, _ := storage.FirstIndex()
	lastindex, _ := storage.LastIndex()
	entries, _ := storage.Entries(firstindex, lastindex+1)
	r := &RaftLog{
		storage:    storage,
		committed:  commit,
		applied:    firstindex - 1,
		stabled:    lastindex,
		entries:    entries,
		FirstIndex: firstindex,
	}
	return r
}
```

我们先给出一个结论，storage实际上就是peer_storage，只不过Project2A用的是测试中提供的一个storage。同时我们在看到newLog函数给出的注释是根据storage返回日志，可以理解为从storage中恢复出日志状态。弄清楚这两点后我们再来看为什么几个指针要这样初始化。

首先是FirstIndex，storage中的FirstIndex函数如下，实际上就是取截断的日志索引的下一索引作为当前第一个日志索引号。这就对应了上面所述RaftLog的功能，未被截断的日志的第一个索引号当然就是被截断的日志索引号+1。因而这地方我们直接从storage中取出第一条日志索引号。
```GO
func (ps *PeerStorage) FirstIndex() (uint64, error) {
	return ps.truncatedIndex() + 1, nil
}
```

然后是LastIndex，storage的LastIndex函数如下，实际上就是取出raftState的中保存的LastIndex，而后面我们会知道这个raftState保存的就是已经持久化的日志状态。因而我们的entries就是storage中所有未被截断的且已经持久化的日志。同时stabled指针也可以确定就是该LastIndex。
```GO
func (ps *PeerStorage) LastIndex() (uint64, error) {
	return ps.raftState.LastIndex, nil
}
```

最后是committed和applied，storage的raftState中的HardState就保存了当前日志的提交情况，因而可以提取出commit指针。由Project2C可知，截断时选择的truncatedIndex实际就是applyIndex，而FirstIndex又是truncatedIndex + 1，因而我们这里初始化的applied就是 firstindex - 1。

#### RaftLog辅助函数
RaftLog的函数均为辅助性函数，这里我们重点说明getEntryIndex、LastIndex、Term三个函数

**getEntryIndex**
由于日志索引与日志在entries中的索引不同，这里我们利用索引号不间断的特性，通过给出索引号与FirstIndex的差距，作为其在entries中的索引。
```GO
func (l *RaftLog) getEntryIndex(i uint64) uint64 {
	return i - l.FirstIndex
}
```

**LastIndex**
LastIndex是一个重要的辅助函数。由于我们已经保存了FirstIndex，这就是我们的第一个日志的索引因而我们可以直接使用索引不间断的特性计算得到最后一个日志的索引。这里我们需要注意entries可能为空，因而这样计算得到的就是FirstIndex - 1，联系前面我们FirstIndex的得到方式，实际上就是truncatedIndex，符合我们的需要。
```GO
// LastIndex return the last index of the log entries
func (l *RaftLog) LastIndex() uint64 {
	// Your Code Here (2A).
	return l.FirstIndex + uint64(len(l.entries)) - 1
}
```

**Term**
直接看代码中的注释即可。
```GO
// Term return the term of the entry in the given index
func (l *RaftLog) Term(i uint64) (uint64, error) {
	// Your Code Here (2A).
    //超出entries长度
	if i >= l.FirstIndex && i-l.FirstIndex >= uint64(len(l.entries)) {
		return 0, ErrUnavailable
	}
    //还在entries以内
	if i >= l.FirstIndex && i-l.FirstIndex < uint64(len(l.entries)) {
		term := l.entries[i-l.FirstIndex].Term
		return term, nil
	}
    //待应用不为空，且需要寻找的index就是快照的index，则直接返回快照的term。
    //这里是为了应对测试点
	if !IsEmptySnap(l.pendingSnapshot) && l.pendingSnapshot.Metadata.Index == i {
		return l.pendingSnapshot.Metadata.Term, nil
	}
    //否则该日志已经被压缩了，需要去storage中找
	term, err := l.storage.Term(i)
	return term, err
}
```

### Raft
该模块用于实现Raft算法，代码文件在raft.go中。模块主要包含三个流程：
* Msg的收发与处理
* 计时器Tick()的实现
* 节点状态的变更

其中Msg的收发与处理用来处理上层下发给Raft节点的消息或节点之间的通信消息，并在Step()中推进。计时器Tick()用于推进逻辑时钟。节点状态的变更用于切换节点的状态并进行相关字段的修改。

#### Msg的收发与处理
Project2A到的消息处理如下图，主要为三种消息处理流程。MsgSnapshot、MsgTransferLeader、MsgTimeoutNow将分别在2C、3A中进行说明。注意，Project2A不用考虑消息如何在节点之间发送，若需要发送消息，只需要将消息推入raft结构中的msgs字段。
![](msg.png)


##### MsgHup
Local Msg，用于请求节点开始选举，需要字段如下：

| 字段    | 作用                  |
|---------|-----------------------|
| MsgType | pb.MessageType_MsgHup |

节点收到该Msg后，会进行相应判断流程，流程如下：
1. 如果节点已经是Leader，则直接返回
2. 判断节点在r.Prs中是否存在，防止节点已经被移出了集群
3. 节点转化为Candidate
4. 判断集群中是否只有一个节点，是的话则直接当选为Leader，不用进入选举步骤。这一步是为了应对测试集。
5. 向其他节点发送请求投票Msg

##### MsgRequestVote
Common Msg，用于请求节点进行投票，需要字段如下：

| 字段    | 作用                          |
|---------|-------------------------------|
| MsgType | pb.MessageType_MsgRequestVote |
| Term    | 节点的term                    |
| LogTerm | 节点的最后一条日志的term      |
| Index   | 节点的最后一条日志的index     |
| To      | 发给谁                        |
| From    | 谁发的                        |

节点收到该Msg后，进行以下处理流程：
1. 如果消息Term小于当前节点的Term，直接拒绝
2. 如果节点已经投了票，并且投票对象不是From，直接拒绝
3. 对比消息来源节点的日志与当前节点的日志谁比较新，若消息来源的日志不是至少与当前节点的日志一样新，直接拒绝（Raft论文-选举限制）
4. 发送同意投票消息，并修改r.Vote

##### MsgRequestVoteResponse
Common Msg，用于节点告诉Candidate投票结果。

| 字段    | 作用                                  |
|---------|---------------------------------------|
| MsgType | pb.MessageType_MsgRequestVoteResponse |
| Term    | 节点的Term，用于更新当前节点的term     |
| Reject  | 是否拒绝投票                          |
| To      | 发给谁                                |
| From    | 谁发的                                |

节点收到该Msg后，进行以下处理流程：
1. 如果不是Candidate，直接返回
2. 更新agreecnt与rejectcnt
3. 若同意数大于集群节点数的一半，直接成为Leader
4. 若拒绝数大于集群节点数的一半，直接成为Follower

##### MsgPropose
Local Msg，用于上层向Raft节点请求提交日志

| 字段    | 作用                      |
|---------|---------------------------|
| MsgType | pb.MessageType_MsgPropose |
| Entries | 需要propose的日志         |
| To      | 发给谁                    |

节点收到该Msg后，进行以下处理流程：
1. 若节点不是Leader或节点正在转移Leader，直接返回
2. 将Msg中的Entries追加到自己的Entries中，并更新r.Prs
3. 若节点中只有一个节点，直接更新committed
4. 向其他节点发送Append消息，进行集群同步

##### MsgAppend
Common Msg，用于Leader向其他节点同步日志

| 字段    | 作用                                                   |
|---------|--------------------------------------------------------|
| MsgType | pb.MessageType_MsgAppend                               |
| To      | 发给谁                                                 |
| From    | 谁发的                                                 |
| Term    | 节点term                                               |
| LogTerm | 要同步的日志的前一条日志的term，即论文中的prevLogTerm   |
| Index   | 要同步的日志的前一条日志的index，即论文中的prevLogIndex |
| Entries | 需要同步的日志                                         |
| Commit  | 当前节点的Commit Index，用于同步已提交节点              |

发送：
1. 先判断需要发送的日志是否已经被压缩，如果被压缩就需要发送快照，否则继续同步日志
2. 节点刚成为Leader时，需要向其他节点发送一条空的日志
3. Leader收到拒绝同步的MsgAppendResponse时，需要更新next并重新发送MsgAppend

接收：
1. 若消息term小于当前节点term，直接拒绝
2. 若prevLogIndex大于当前节点最后一条日志的Index，说明无法匹配，直接拒绝
3. 查找当前节点entries中是否有一条日志的term和index能与prevLogTerm、prevLogIndex匹配，若找不到，直接拒绝
4. 根据论文及测试点进行日志的追加，并删除冲突条目
    * 找到Msg中entries与节点entries最后一个匹配的位置，记录为lastMatchIndex
    * 若Msg中entries全部匹配，则不需要进行截断，否则往下
    * 截断节点entries中冲突的部分，并追加Msg的entries剩余部分到节点entries中
    * 更新stabled指针，因为可能出现已经持久化的日志被新来的日志覆盖。（此处是面向测试写出来的）
5. 更新commit指针为 Leader 已知已经提交的最高的日志条目的索引 m.Commit 或者是上一个新条目的索引两者中的最小值。（论文中有写）
6. 发送成功同步回复

##### MsgAppendResponse
Common Msg，用于节点向Leader回复日志同步情况

| 字段    | 作用                                       |
|---------|--------------------------------------------|
| MsgType | pb.MessageType_MsgAppendResponse           |
| To      | 发给谁                                     |
| From    | 谁发的                                     |
| Term    | 节点term                                   |
| Reject  | 是否拒绝                                   |
| Index   | r.RaftLog.LastIndex()，用于给Leader更新next |

节点收到该Msg后，处理流程如下：
1. 只有Leader能处理该消息
2. 若Reject == true，更新next。重置规则为：先将next--，在将其与Msg中的Index + 1比较，取最小值作为next，这样是为了快速找到需要同步给节点的日志起始索引。随后重新尝试同步日志
3. 若Reject == false，更新match = msg.Index，next = msg.Index + 1，这样下次同步日志就可以从该节点没有的日志开始同步了。继续往下
4. 尝试更新Leader的committed指针，更新规则在论文中有说，即假设存在 N 满足N > commitIndex，使得大多数的 matchIndex[i] ≥ N以及log[N].term == currentTerm 成立，说明日志已经同步到大多数节点上了，则令 commitIndex = N。如果committed指针变化，需要直接向所有节点发送append消息，用于同步提交情况。

##### MsgBeat
Local Msg，用于上层向Raft告知需要发送心跳

| 字段    | 作用                   |
|---------|------------------------|
| MsgType | pb.MessageType_MsgBeat |

节点收到该Msg后，处理流程如下：
1. 只有Leader能处理该消息
2. 向其他节点发送心跳

##### MsgHeartBeat
Common Msg，Leader发送的心跳，与Raft论文不同，TinyKv中的心跳是一个单独的消息类型，而非空的AppendEntries

| 字段    | 作用                                                                                  |
|---------|---------------------------------------------------------------------------------------|
| MsgType | pb.MessageType_MsgHeartBeat                                                           |
| From    | 谁发的                                                                                |
| To      | 发给谁                                                                                |
| Term    | 节点term                                                                              |
| Commit  | util.RaftInvalidIndex，实际上就是0。原因是Project3B中Leader用心跳创建peer会检查该commit |

发送：
1. Leader收到MsgBeat时，会主动发送
2. Leader心跳超时，会向其他节点发送心跳

接收：
1. 若msg.term >= 节点term，需要转化为Follower
2. 重置选举计时
3. 发送MsgHeartBeatResponse

##### MsgHeartBeatResponse
Common Msg，用于向Leader告知心跳回应

| 字段    | 作用                                            |
|---------|-------------------------------------------------|
| MsgType | pb.MessageType_MsgHeartBeatResponse             |
| From    | 谁发的                                          |
| To      | 发给谁                                          |
| Term    | 节点term                                        |
| Commit  | 节点的committedIndex，用于告知Leader日志提交情况 |

处理流程如下：
1. 只有Leader能处理
2. 判断msg.commit 是否小于节点commit，是则说明该Follower落后了，需要发送AppendEntries，进行日志同步。


#### 计时器Tick()
Tick()是一个逻辑时钟，由RawNode提供的Tick接口供上层使用，用于推进计时。

##### Follower
每次调用Tick()，都要进行r.electionElapsed++，并判断如果选举超时，则直接调用Step()进行选举。
##### Candidate
与Follower步骤相同
##### Leader
作为Leader，当选举超时，要重置r.electionElapsed，并判断是否有正在转移的节点，是则说明没有转移成功，要放弃转移。

同时Leader还需要进行心跳计时，并在心跳超时后，重置心跳计时并向所有节点发送心跳。

#### 节点状态变更
Follower和Candidate的状态变更都比较简单，这里重点讲解Leader节点变更时需要进行的操作：
1. 重置Vote、agreecnt、rejectcnt、leadTransferee、electionElapsed等字段
2. 更新State和Lead
3. 更新r.Prs，其中next为LastIndex + 1，match为0
4. 更新PendingConfIndex。这是因为日志中可能有ConfChange操作，需要更新该索引。
5. 利用Propose，发送一条空日志（noop entry）

#### 一些想法
此部分主要依靠Raft论文实现Raft基本逻辑，需要进行适当的面向测试集编程。在测试函数中我们可以知道，测试并没有真正将消息发送出去，而是直接从msgs中取出消息进行检查，相应的消息发送将在Project2B中用到。

### RawNode
RawNode是上层与Raft联系的桥梁。上层通过RawNode中的HasReady判断是否有准备好的Ready，然后直接取出Ready进行操作，包括持久化日志、发送消息、应用日志、应用快照，这些都是之后会进行实现的。这里我们说一下HasReady和Advance的思路。

#### HasReady
* 判断是否有未持久化的日志
* 判断是否有待应用的日志
* 判断是否待发送的日志（消息是交给上层进行发送的）
* 判断HardState是否发生了改变
* 判断是否有待应用的快照

#### Advance
上层根据之前传上去的Ready做出相应操作后，返回到Raft节点，也需要进行相应的修改：
* 修改prevSoftState
* 修改prevHardState
* 修改stabled指针
* 修改applied指针
* 调用maybeCompact，判断是否发生了日志压缩，进而抛弃内存中的已经截断的日志
* 清空待应用快照
* 清空待发送消息

## Project2B
在这一部分中，我们将使用 Part A 中实现的 Raft 模块建立一个容错的KV存储服务。具体而言，我们在Project2A中没有考虑消息的发送，在这一部分中，我们就会实现消息的发送与处理。同时在Project2A中我们也没有考虑日志到底是如何持久化以及应用的，只是进行了指针的修改，这一部分我们就会实现日志在磁盘中持久化已经真正地应用。

### 存储服务的读写流程
* 客户端Client调用server中提供的Get、Put、Snap、Delete四种操作函数
* RPC 处理程序调用 RaftStorage 的相关方法
  * 与Project1一样，storage是engine的一个封装，并提供了Start、Stop、Write、Reader四种基本函数供server层使用
* RaftStorage 向 raftstore 发送一个 Raft 命令请求，并等待响应
  * 调用Get、Put、Snap、Delete等函数实际就是调用storage中的Write、Reader函数
  * RaftStorage实际会利用router向其raftstore中的peer发送命令，router就注册了当前raftstore中的所有peer，具体如下。可见RaftStorage通过router向peerSender通道发送了消息，接下来消息就会传送到RaftWorker中，并进一步处理
```GO
func (pr *router) send(regionID uint64, msg message.Msg) error {
	msg.RegionID = regionID
	p := pr.get(regionID)
	if p == nil || atomic.LoadUint32(&p.closed) == 1 {
		return errPeerNotFound
	}
	pr.peerSender <- msg
	return nil
}
```
* RaftStore 将 Raft 命令请求作为 Raft Log 提出
  * 消息发送到peerSender后，会通过raftCh传送到raftWorker中
  * raftWorker会为每一条命令的发送对象创建一个peer_msg_handler，进行命令的处理，如下。
```Go
  func (rw *raftWorker) run(closeCh <-chan struct{}, wg *sync.WaitGroup) {
	defer wg.Done()
	var msgs []message.Msg
	for {
		msgs = msgs[:0]
		select {
		case <-closeCh: //发来close消息时，就停止工作
			return
		case msg := <-rw.raftCh: //有peerSender的消息,全部接收
			msgs = append(msgs, msg)
		}
		pending := len(rw.raftCh)
		for i := 0; i < pending; i++ {
			msgs = append(msgs, <-rw.raftCh)
		}
		peerStateMap := make(map[uint64]*peerState)
		for _, msg := range msgs {
			peerState := rw.getPeerState(peerStateMap, msg.RegionID)
			if peerState == nil {
				continue
			}
			//这里很关键，传入了GlobalContext,因而是需要peer_msg_handler对storeMeta进行修改的
			newPeerMsgHandler(peerState.peer, rw.ctx).HandleMsg(msg)
		}
		for _, peerState := range peerStateMap {
			newPeerMsgHandler(peerState.peer, rw.ctx).HandleRaftReady()
		}
	}
}
```

* peer_msg_handler提交命令，并将命令同步到raft层
```GO
func (d *peerMsgHandler) proposeRaftCommand(msg *raft_cmdpb.RaftCmdRequest, cb *message.Callback) {
	err := d.preProposeRaftCommand(msg)
	if err != nil {
		cb.Done(ErrResp(err))
		return
	}
	// Your Code Here (2B).
	if msg.AdminRequest != nil {
		d.proposeAdminRequest(msg, cb)
	} else {
		d.proposeRequest(msg, cb)
	}
}
```

* Raft 模块添加该日志，并由 PeerStorage 持久化
  * HandlerRaftReady中将会把需要持久化的日志进行持久化
* Raft Worker 在处理 Raft Ready 时执行 Raft 命令，并通过 callback 返回响应
  * HandlerRaftReady中也会将需要应用的日志进行应用
  * 应用完日志后，需要通过callback返回响应，这样上层在能知道指令是否得到了执行，也可能没有完成执行，就需要重新进行执行。
* RaftStorage 接收来自 callback 的响应，并返回给 RPC 处理程序
* RPC 处理程序进行一些操作并将 RPC 响应返回给客户

到此为止我们就基本了解了整个TinyKv基本的读写流程，其中大部分是不需要我们实现的，但了解整个流程对我们的实现有很大帮助。

现在我们可以给出结论，我们需要实现的部分就是在proposeRaftCommand中将Raft命令提出，并propose到raft层进行同步。随后在HandlerRaftReady中处理raft层传来的ready，包括日志持久化、快照应用、消息发送、日志应用等。

### proposeRaftCommand
我们首先分析RaftCmdRequest的结构。Header中携带了消息的region、peer等信息。Requests中包含了Get、Put、Delete、Snap四种操作类型。AdminRequest包含了四种请求，我们将在2C、3A、3B中遇到。
```GO
type RaftCmdRequest struct {
	Header *RaftRequestHeader 
	// We can't enclose normal requests and administrator request
	// at same time.
	Requests             []*Request    
	AdminRequest         *AdminRequest 
	XXX_NoUnkeyedLiteral struct{}      
	XXX_unrecognized     []byte        
	XXX_sizecache        int32         
}
```

propose步骤分两步：
* 为msg创建一个proposal，包括它在entries中的index、term和callback。在后续entry应用后，需要响应该proposal，通过callback.Done()来传递响应。
* 通过msg.Marshal()将请求包装成字节流，这样就可以放在entry的data中了。然后通过d.RaftGroup.Propose()将该字节流传递给RawNode包装成entry，并进行raft层的同步。

这里需要说一下proposal的作用，上层向下层传达命令，需要知道命令是否得到了执行，这就是callback的作用。proposal包含了index、term、callback，当entry应用后，需要通过index、term找到该entry对应的proposal，然后利用callback.Done()来传递响应。

### HandleRaftReady
该部分用于处理rawNode传递来的Ready，主要分为5步：
* 判断有没有ready，没有则直接返回
* 调用SaveReadyState持久化Ready中需要持久化的日志
* 判断是否应用了快照，如果是，需要修改StoreMeta
* 调用d.Send()将Ready中待发送的消息发出
* 应用Ready中的CommittedEntries
* 调用d.RaftGroup.Advance()

#### SaveReadyState
* 判断有没有快照，有的话调用ApplySnapshot应用快照
* 调用Append将需要持久化的日志写入raftDB中，注意需要修改raftState的LastIndex与LastTerm
* 判断HardState是否为空，不为空需要修改RaftState中的HardState
* 持久化RaftState
* 通过 raftWB.WriteToDB 和 kvWB.WriteToDB 进行底层写入

**关于写入编码**

| Key              | KeyFormat                        | Value            | DB   |
|------------------|----------------------------------|------------------|------|
| raft_log_key     | 0x01 0x02 region_id 0x01 log_idx | Entry            | raft |
| raft_state_key   | 0x01 0x02 region_id 0x02         | RaftLocalState   | raft |
| apply_state_key  | 0x01 0x02 region_id 0x03         | RaftApplyState   | kv   |
| region_state_key | 0x01 0x03 region_id 0x01         | RegionLocalState | kv   |

我们需要使用 engine_util 中的 WriteBatch 来进行原子化的多次写入。利用WriteBatch.SetMeta与WriteBatch.DeleteMeta写入WriteBatch中，并结合上述的编码格式。例如：entry的写入编码为 raftWB.SetMeta(meta.RaftLogKey(ps.region.Id, ent.Index), &ent) 可以看到我们先利用meta.RaftLogKey得到Key，Value就是Entry。

#### applyRequest
这里我们需要注意，在TinyKv中有两个badger实例，一个是raftDB，一个是kvDB。raftDB 存储 raft 日志和 RaftLocalState。kvDB 在不同的列族中存储键值数据，RegionLocalState 和 RaftApplyState。可以把 kvDB 看作是Raft论文中提到的状态机。这一部分我们只需要判断request的类型，包括Get、Put、Delete、Snap，然后进行写入或读出操作即可，然后需要进行handleProposal。

**关于handleProposal**
一般来说如果没有网络延迟中断、没有leader变更，proposals中的顺序与entries中的顺序是一样的。但由于会出现leader变更，导致一些日志被后来的leader日志所覆盖，从而永远不会执行。但这时上层是不知道的，因此会继续等待，而我们就需要将这些日志进行回复，并对已经执行的日志进行响应。我们按照index、term进行以下分类

* p.index小于ent.index
由于我们是按照顺序执行entry的，因而如果出现proposal中有小于当前entry.index的出现，就说明该日志已经过期了，要返回ErrRespStaleCommand
* p.index大于ent.index
这是不可能出现的，原因和上面一样，如果有ent的执行，就一定会有proposal弹出
* p.index等于ent.index
  * p.term != ent.term：这也说明该proposal是过期的，要返回ErrRespStaleCommand
  * p.term == ent.term：这就是当前ent对应的proposal，通过cb.Done()返回响应

## Project2C
本部分需要实现日志压缩与快照的相关功能。对于一个长期运行的服务器来说，永远记住完整的Raft日志是不现实的。相反，服务器会检查Raft日志的数量，并不时地丢弃超过阈值的日志，这就是日志压缩。在Raft层进行日志同步的过程中，可能出现需要同步的日志已经被压缩的情况（通常是一个节点宕机后重新启动或新增的一个节点），这时就需要Leader生成快照，快照包含了某个时间点状态机的全部内容，将此快照发给需要的节点，从而实现快照应用。

### 触发流程
**日志压缩**
在onTick中的d.onRaftGCLogTick()，会检查已经当前已经应用的日志是否超出了阈值，因为这些已经应用的日志已经没有用了，所以就不用保存在raftDB中了，因而就会触发日志压缩的流程。流程将会生成一个日志压缩的adminRequest并进行propose，随后raft层同步该adminRequest。之后会在HandleRaftReady中应用该操作，从而实现日志压缩操作，并通过maybeCompact压缩内存中的日志。

**快照流程**
日志压缩时，内存中的日志也会跟着压缩，那么就有可能出现Leader在同步日志时发现需要同步的日志已经被压缩了，这时就说明该节点已经落后于Leader了，需要生成快照并发送。节点收到快照后，要抛弃自己已有的日志，因为快照中包含了某个时间点的所有信息，并更新自己的各个指针。接着就会在HandleRaftReady中进行快照的应用。

### 流程详解
流程可以分为四个部分：日志压缩、快照生成与分发、快照接收、快照应用

**日志压缩**
1. 通过proposeCmdCompactLog将日志压缩的命令propose到raft层中，同步给同一region的其他节点。
2. 在applyCompactLog进行日志压缩的应用。我们需要更新applyState中的TruncatedState，并调用d.ScheduleCompactLog( ) 发送 raftLogGCTask 任务给 raftlog_gc.go。raftlog_gc.go 收到后，会删除 raftDB 中对应 index 以及之前的所有已持久化的 entries，以实现压缩日志。这里我们需要注意peer_storage中的FirstIndex()函数,可以看到peer_storage的firstIndex实际就是truncatedIndex + 1。
```GO
func (ps *PeerStorage) FirstIndex() (uint64, error) {
	return ps.truncatedIndex() + 1, nil
}
```
3. 调用proposal进行响应。
4. 在advance中调用maybeCompact，更新内存entries中的日志，丢弃已经被压缩掉的日志。

需要注意的是，日志压缩和快照流程可以算是分离的，快照流程只有在上述的触发流程中才会启动。也可以理解为必须先有日志压缩，才可能有快照流程。

**快照生成与分发**
1. 在Leader进行sendAppend，若next小于firstIndex，则说明需要同步的日志已经被压缩了，因而需要调用sendSnapshot
2. 若pendingSnapshot != nil，表示有待应用的快照，就直接发送这个，否则需要重新生成。
3. 调用peer_storage中的Snapshot，由于该函数不是立刻完成的，因而如果返回值为空，表示还没生成好，就需要放弃本次发送。否则就可以进行发送。

注意，快照发送实际偏移了sendAppend的本意，所以如果调用了sendSnapshot，sendAppend就应该返回false。（不过好像也没什么关系）

**快照接收**
1. 如果快照的term小于节点term，直接拒绝
2. 如果快照的index小于节点的committed，也得拒绝。因为已经commit的日志就一定会被应用，若接收了日志，就会丢弃这些已经提交的日志。
3. 到这一步就正常接收快照。我们的策略是丢弃已有的日志，全部替换为快照，因而FirstIndex、committed、applied、stabled、entries都需要进行更新。pendingSnapshot进行赋值。
4. 根据Snapshot中的ConfState更新r.Prs。
5. 发送AppendResponse进行回复。

**快照应用**
1. 在saveRaftState时，若Snapshot不为空，就需要调用ApplySnapshot
2. 通过clearMeta和clearExtraData清空旧的数据。这是因为要通过快照应用整个状态机的数据。
3. 更新raftState和applyState，并进行相应持久化。
4. 按照文档的说法，需要给 snapState.StateType 赋值为 snap.SnapState_Applying。
5. 生成一个 RegionTaskApply，传递给 ps.regionSched 管道即可。region_task.go 会接收该任务，然后异步的将 Snapshot 应用到 kvDB 中去。
6. 持久化region状态
7. 若region发生了变化，需要修改storeMeta，以及peer_storage.region


