# Task #1 - Lock Manager
LM 的基本思想是它维护一个有关活动事务当前持有的锁的内部数据结构。然后，事务在被允许访问数据项之前向 LM 发出锁定请求。LM 将向调用事务授予锁定、阻止该事务或中止它。

我们需要支持三种隔离级别`READ_UNCOMMITED`, `READ_COMMITTED`, 和 `REPEATABLE_READ`

任何失败的锁定操作都将导致事务的ABORTED，并抛出异常。

## LockTable(Transaction, LockMode, TableOID)
关于锁表，我们需要分为四个步骤：
1. 检查合法性
2. 获取请求队列
3. 判断是否为更新操作
4. 等待并获取锁
5. 更新transaction的lock set

**检查合法性**
这一部分由【LOCK_NOTE】可知，主要是检查隔离级别、事务阶段与需要上的锁是否冲突，见下：
- REPEATABLE_READ：
	- All locks are allowed in the GROWING state
	- No locks are allowed in the SHRINKING state
- READ_COMMITTED：
	- All locks are allowed in the GROWING state
	- Only IS, S locks are allowed in the SHRINKING state
- READ_UNCOMMITTED：
	- X, IX locks are allowed in the GROWING state
	- S, IS, SIX locks are never allowed

**获取请求队列**
我们有一个table_oid_t->LockRequestQueue的table_lock_map，为了保证并发性，需要进行上锁并获取对应oid的LockRequestQueue。

具体如下：
![[Pasted image 20231221110227.png]]

**获取并等待锁**
- 创建LockRequest并放入LockRequestQueue的末尾，遵循FIFO的规则。
- 创建一个std::unique_lock，用于睡眠锁
- 通过LockRequestQueue的std::condition_variable进入睡眠，直到被唤醒。
- 事务进程被唤醒后，自动获取睡眠锁，并做如下检查：
	- 如果事务已经被ABORTED，移除LockRequest，并返回false
	- 如果事务还没有获得对应的表锁，继续睡眠
	- 如果事务获得了对应的表锁，进入下一阶段。

**更新transaction的lock set**
transaction维护了所有类型的lock set，我们需要根据获取的锁类型插入到对应的set中。

**判断是否为更新**
上锁也可能出现upgrade的情况，即将已经上的锁进行升级，这一部分在【LOCK_NOTE】也有提到。

我们需要遍历LockRequestQueue，查看是否有该事务上的锁，如果有，就说明是upgrade的情况。

接下来需要对更新合法性进行检查，如果升级的条件不符合，就需要抛出异常并终止事务。

然后就需要删除已有的锁，并新建一个更新后的LockRequest并插入到请求队列的最前端，优先处理，剩下就和获取并等待锁差不多了。

## UnlockTable(Transction, TableOID)
**合法性检查**
对于解锁表锁，首先要检查该事务是否有在该表下未释放的行锁。
其次还需要检查是否不存在表锁。

**获取请求队列**
依次上锁，获取LockRequestQueue。

**将锁从请求队列中移除**
我们需要从请求队列中将该锁移除，并修改事务的状态为SHRINKING，修改事务的lock set。

# Task #2 - Deadlock Detection
死锁检测通过事务依赖图来判断是否存在环，如果有环就说明有死锁，就需要进行打破。

**建图**
我们需要遍历表锁的请求队列和行锁的请求队列，从未获取锁的事务建立一条到已获取锁的事务的边。

此处我们采用邻接表作为存图的数据结构。

**判环**
采用DFS，按照文档给定的搜索顺序，一旦DFS过程中遍历到了重复的点，就说明存在环，也就是存在死锁。

**破环**
破环需要找到最年轻的事务（也就是txn_id最大）进行终止，同时需要删除该事务在图中的节点和相应的边。

每终止一个事务，都需要提醒事务对应的请求队列，从而让请求队列中的事务唤醒，并继续获取锁

循环直到图中不存在环，就说明不存在死锁。

# Task #3 - Concurrent Query Execution
在并发查询执行期间，执行器需要适当地锁定/解锁元组，以达到相应事务中指定的隔离级别。为了简化此任务，您可以忽略并发索引执行，而只关注表元组。

此处我们需要更新sequential scan、insert、delete三个Executor

**sequential scan**
首先要在对应表上IS锁，然后每次next都需要在对应行上S锁。

遍历结束后，根据隔离级别，如果隔离级别为READ_COMMITTED，就需要解锁全部S锁和IS锁。

**insert**
首先要在对应表上IX锁，然后每次next插入后，要在对应行上X锁。

**delete**
首先要在对应表上IX锁，然后每次next删除前，要在对应行上X锁。


