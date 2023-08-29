- [Project3](#project3)
  - [Project3A](#project3a)
    - [TransferLeader](#transferleader)
    - [ConfChange](#confchange)
  - [Project3B](#project3b)
    - [TransferLeader](#transferleader-1)
    - [ConfChange](#confchange-1)
    - [Split](#split)
    - [3B疑难杂症](#3b疑难杂症)
  - [Project3C](#project3c)
    - [processRegionHeartbeat](#processregionheartbeat)
    - [Schedule](#schedule)

# Project3
## Project3A
该部分主要实现了TransferLeader、ConfChange在Raft层的实现，较为简单，但却是Project3B的基础
### TransferLeader
RawNode.TransferLeader会将MsgTransferLeader进行step，从而进入我们handleTransferLeader的函数，处理流程如下：
1. 节点必须是Leader，否则直接返回
2. 判断被转移节点在r.Prs中，因为可能出现被转移节点已经被移出集群的情况，这时候就要直接返回
3. 若当前有正在转移的对象，或被转移对象就是当前Leader，直接返回
4. 判断被转移对象是否满足Leader要求，结合Raft论文的选举限制，就是该被转移Leader必须有全部已提交日志，在此我们可以用match是否与Leader完全匹配来判断。若满足要求可以直接发送MsgTimeoutNow。不满足要求则需要发送AppendEntries进行日志同步，帮助该节点尽快完成同步，之后再handleAppendResponse处要判断，一旦同步完成，就发送MsgTimeoutNow。
5. 节点收到MsgTimeoutNow后，立刻开始选举

注意：
1. 转移阶段不能进行propose，要直接拒绝。
2. 必须要在节点由Leader转为Follower后才能取消leadTransferee，否则可能出现还未转移成功，上层就接着向该节点进行propose。

### ConfChange
RawNode.ApplyConfChange会根据ConfChange类型进行addNode或removeNode，此处只用进行raft层的增删节点，真正的增删节点将在Project3B中实现。

**addNode**
若r.Prs为空，则进行节点增加。若当前节点为Leader，还需要初始化next与match。

**removeNode**
若r.Prs存在，则进行节点删除。同时如果当前节点为Leader，需要重新尝试更新committedIndex，防止出现节点在发送AppendResponse之前就被remove了，导致Leader不会更新committed。

## Project3B
该部分涉及TransferLeader、ConfChange、Split三种Admin命令的propose与应用处理。
### TransferLeader
TransferLeader用于在一个region中转移Leader。该命令较为特别，不需要同步到集群中的其他节点，只需要由Leader单独执行即可。
1. 在proposeCmdTransferLeader中调用d.RaftGroup.TransferLeader()，即可直接向raft层step一个MsgTransferLeader，随后进入raft层处理，流程与Project3A相同。
2. 进行callback的响应。

### ConfChange
ConfChange用于增加或删除一个region中的节点。该命令的propose过程与其他命令的流程相似，只是注意此处使用d.RaftGroup.ProposeConfChange()进行提交，RaftCmdRequest需要打包在context中一同propose。

**应用流程如下：**
1. 在applyCommittedEntry中判断该日志为EntryType_EntryConfChange，调用applyConfChange
2. 将context反序列化得到RaftCmdRequest
3. 调用CheckRegionEpoch()，检查该命令是否过期，如果过期就不能再执行了，防止重复执行ConfChange
4. 根据ConfChange类型，修改region的peer，是增加就增加，是移除就移除。若需要移除的节点就是当前节点，调用d.destroyPeer()，真正移除该节点，直接返回。
5. region.RegionEpoch.ConfVer++
6. 更新StoreMeta，将region进行替换。用于保证raftStore的StoreMeta信息是正确的
7. 调用 d.insertPeerCache() 或 d.removePeerCache() 方法。PeerCache是用于节点发送消息时，取出发送对象的peer
8. 调用meta.WriteRegionState()，持久化region信息。
9. 调用d.RaftGroup.ApplyConfChange()
10. 处理proposal
11. 调用notifyHeartbeatScheduler()，向scheduler发送心跳，更新region信息。

**关于增加节点**
通过上面的流程，我们在增加节点时，实际上只是在raft层创建了节点，让region的各节点知道存在一个新节点，但这个新节点并没有真的存在，不像移除节点时显式调用了destroyPeer。文档中给出的说法是，新添加的 Peer 将由领导者的心跳来创建，下面我们就来细究这个过程。

1. Leader会向新增的节点发送心跳，在发送心跳之前的其他信息都会被滤除，因为节点并没有创建好。
2. Leader通过transprot发送消息，最终传递到router中进行消息发送
```GO
func (r *RaftstoreRouter) SendRaftMessage(msg *raft_serverpb.RaftMessage) error {
	regionID := msg.RegionId
	if r.router.send(regionID, message.NewPeerMsg(message.MsgTypeRaftMessage, regionID, msg)) != nil {
		r.router.sendStore(message.NewPeerMsg(message.MsgTypeStoreRaftMessage, regionID, msg))
	}
	return nil
}
```
3. router先尝试直接发给peer，不行后就发送给当前store，即发送到store_worker，在store_worker处理消息时，发现节点可能没有创建，就会调用maybeCreatePeer
```GO
func (d *storeWorker) maybeCreatePeer(regionID uint64, msg *rspb.RaftMessage) (bool, error)
```
4. 到这个函数，节点就真正被创建了，将被注册到router中，并发送MsgTypeStart进行启动

**关于region更新**
新创建的节点region信息为空，因而会由Leader发送一个快照，让新创建的节点跟上进度，并更新region信息，这就是为什么HandleRaftReady中需要在saveRaftState后更新StoreMeta的原因。

### Split
Split用于一个region的容量超出阈值时，进行分裂操作，生成两个region。一方面这样可以进行更精细的处理，另一方面这样实现了并发性，提高了访问性能。
![](project3/keyspace.png)

**Split触发**
1. 与日志压缩类似，在onTick的onSplitRegionCheckTick()中会检查当前region是否满足split要求，如果满足就会发送一个SplitCheckTask到split_checker中。
2. split_checker会找到用于分割region的key，保证region一分为二
3. split_checker生成一个MsgTypeSplitRegion，并发送给对应region
4. 在 peer_msg_handler.go 中的 HandleMsg() 方法中调用 onPrepareSplitRegion()，发送 SchedulerAskSplitTask 请求到 scheduler_task.go 中，申请其分配新的 region id 和 peer id。申请成功后其会发起一个 AdminCmdType_Split 的 AdminRequest 到 region 中。
5. 接着就和其他admin命令一样，将该命令进行propose。注意 propose 的时候检查 splitKey 是否在目标 region 中和 regionEpoch 是否为最新，因为目标 region 可能已经产生了分裂。

**Split应用**
1. 再次进行CheckKeyInRegion与IsEpochStale的检查，保证该命令没有过期
2. 将当前region clone一份，命名为newRegion，并进行相应修改：
   1. 将newRegion 的 peers的Id替换为命令中的新Id
   2. 将newRegion的 Id 修改为为 req.Split.NewRegionId，StartKey 修改为为 req.Split.SplitKey，EndKey 为原来的EndKey。
   3. 修改oldRegion的EndKey为SplitKey
3. oldRegion 和 newRegion 的 RegionEpoch.Version 均自增；
4. 将两个region进行持久化
5. 更新StoreMeta，包括修改regions，删除regionRanges中旧的region，并插入新的region。
6. 通过 createPeer() 方法创建新的 peer 并注册进 router，同时发送 message.MsgTypeStart 启动 peer
7. 调用两次 d.notifyHeartbeatScheduler()，更新 scheduler 那里的 region 缓存

### 3B疑难杂症
**执行完ConfChange后要判断stop，若已经被移除，则不能进行之后的entry应用**
在ConfChange时，可能出现移除的节点就是本身，这时就不能在继续执行之后的日志了。

**Snap操作时，返回的region应该使用clone的region**
这是因为在响应Snap操作到上层使用这个region的期间，该region可能发生split的情况，那么region的信息就被修改了，因而我们在Snap操作时应该返回一个clone的region。
```GO
oldregion := new(metapb.Region)
util.CloneMsg(d.Region(), oldregion)
resp.Responses = append(resp.Responses, &raft_cmdpb.Response{
CmdType: raft_cmdpb.CmdType_Snap,
Snap:    &raft_cmdpb.SnapResponse{Region: oldregion},
})
```

**在执行移除节点时，若集群中只有两个节点，且自己就是那个要被移除的节点，需要先执行transferLeader**
这是因为可能出现移除节点后，集群中另一个节点没有收到节点移除的信息，导致该节点认为集群中仍有两个节点，就会无法当选为Leader，因而我们应该显式执行transferLeader。

## Project3C
该部分要实现一个上层的调度器，调度器的功能在project.md里已有阐述，具体可查看那篇文档。这里我们要实现在区域心跳的收集处理与区域平衡器。

### processRegionHeartbeat
该函数需要对收集到的区域心跳进行处理，更新本地region记录，流程如下：
1. 检查本地存储中是否有一个具有相同 Id 的 region。如果有，并且至少有一个心跳的 conf_ver 和版本小于它，那么这个心跳 region 就是过时的。
2. 如果没有，则扫描所有与之重叠的区域。心跳的 conf_ver 和版本应该大于或等于所有的，否则这个 region 是陈旧的。
3. 使用 RaftCluster.core.PutRegion 来更新 region-tree ，并使用 RaftCluster.core.UpdateStoreStatus 来更新相关存储的状态

### Schedule
region balance调度器避免了在一个 store 里有太多的 region。流程如下：
1. 选出 DownTime() < MaxStoreDownTime 且状态为Up的store作为我们备选的store，并将他们按regionSize进行降序排列
2. 找到源store和需要转移的region
   1. 从大到小遍历备选store
   2. 利用GetPendingRegionsWithLock, GetFollowersWithLock 和 GetLeadersWithLock获取需要转移的region
   3. 找到了待转移的region就执行下面步骤，否则重复上述步骤
3. 判断目标 region 的 store 数量，如果小于 cluster.GetMaxReplicas()，直接放弃本次操作
4. 找到可以接收转移region的store
   1. 从小到大遍历备选store
   2. 若待转移region不在该store中，则可以选择
5. 判断两 store 的 regionSize 差别是否过小，如果是（< 2*ApproximateSize），放弃转移。因为如果此时接着转移，很有可能过不了久就重新转了回来
6. 利用cluster.AllocPeer()在目标store上创建一个peer，并调用operator.CreateMovePeerOperator()生成转移请求
