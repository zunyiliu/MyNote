# Crash Recovery
本节我们主要讲事故发生后，如何将数据库恢复到事故前的ACID状态。

语义恢复和隔离算法（ARIES）是 IBM 在 20 世纪 90 年代初为 DB2 系统开发的一种恢复算法。在ARIES算法中有三个关键概念：
- Write Ahead Logging：在数据库更改写入磁盘之前，任何更改都将记录在稳定存储的日志中(STEAL+NO-FORCE)
- Repeating History During Redo：重新启动时，回溯操作并将数据库恢复到崩溃前的确切状态
- Logging Changes During Undo：将撤销操作记录到日志中，以确保在重复失败的情况下不重复操作

# WAL Records
Write-ahead log 记录扩展了 DBMS 的日志记录格式，以包含一个全局唯一的日志序列号(LSN)

所有日志记录都有一个 LSN，系统中的各种组件跟踪与它们相关的 LSN，如下：
![[Pasted image 20231217150415.png]]
- 每个data page都有一个pageLSN，是该page的最近一次更新的LSN
- flushedLSN表示最近一次刷新到磁盘的日志LSN
- ![[Pasted image 20231217150820.png]]

# Normal Execution
## Transaction Commit
- 当事务提交时，DBMS 首先将 COMMIT 记录写入内存中的日志缓冲区
- 然后，DBMS 将所有日志记录(包括事务的 COMMIT 记录)刷新到磁盘
- 一旦 COMMIT 记录被安全地存储在磁盘上，DBMS 就会向应用程序返回事务已提交的确认信息
- 稍后， DBMS 将向日志中写入一条特殊的 TXN-END 记录。这表明事务在系统中已经完全完成。
- 这些 TXN-END 记录用于内部簿记，不需要立即刷新

## Transaction Abort
- 中止事务是 ARIES 撤消操作的一个特例，只适用于一个事务 
- 我们需要在日志记录中添加一个名为 prevLSN 的附加字段。这对应于事务的前一个LSN。
- DBMS 使用这些 prevLSN 值为每个事务维护一个链表，这样可以更容易地遍历日志以查找其记录

我们还还引入了一种称为补偿日志记录(CLR)的新记录类型：
- 它记录了为撤销前一个更新记录的操作而采取的操作
- 它包含更新日志记录的所有字段，外加撤销下一步指针（即下一个要撤销的 LSN ）
- DBMS 像添加任何其他记录一样将 CLR 添加到日志中，但它们永远不需要被撤销
![[Pasted image 20231217153620.png]]

中止流程如下：
- DBMS 首先将 abort 记录附加到内存中的日志缓冲区中
- 然后，它按反向顺序撤销事务的更新， 以从数据库中删除它们的影响
- 对于每个未完成的更新，DBMS 在日志中创建 CLR 条目并恢复旧值
- 在所有被终止的事务的更新都被逆转之后，DBMS 就会写一条 TXN-END 日志记录

# Checkpointing
DBMS 定期设置检查点，将缓冲池中的脏页写到磁盘上。这是用来减少恢复时重放日志的数量。

## Blocking Checkpoints
当 DBMS 采用检查点以确保将数据库的一致快照写入磁盘时，它会停止事务和查询的执行
- 停止任何新事务的开始
- 等待所有活动事务执行完毕
- 将脏页刷写到磁盘

## Slightly Better Blocking Checkpoints
与之前的检查点方案类似，DBMS 不需要等待活动事务完成执行。DBMS 现在记录检查点开始时的内部系统状态：
- 停止任何新事务的开始
- 在 DBMS 执行检查点时暂停事务

**Active Transaction Table (ATT)**
ATT 表示 DBMS 中活动运行的事务的状态 。事务的条目在 DBMS 完成事务的提交/中止过程后被删除。对于每个事务条目，ATT 包含以下信息：
- transactionId：唯一的事务id
- status：事务当前的状态（ Running, Committing, Undo Candidate ）
- lastLSN：该事务的最近一个LSN

**Dirty Page Table (DPT)**
DPT 包含缓冲池中被未提交事务修改的页的信息。每个脏页都有一个包含 recLSN 的条目(即，首先导致该页变脏的日志记录的 LSN)

DPT 包含缓冲池中所有脏的页面。这些更改是由正在运行的事务、提交的事务还是中止的事务引起的并不重要

总的来说，ATT 和 DPT 通过 ARIES 恢复协议帮助 DBMS 恢复崩溃前的数据库状态

## Fuzzy Checkpoints
模糊检查点是 DBMS 允许其他事务继续运行的地方。这就是 ARIES 在其协议中使用的。DBMS 使用额外的日志记录来跟踪检查点边界。
- < CHECKPOINT-BEGIN >：检查点的起始点。此时， DBMS 获取当前 ATT 和 DPT 的快照，它们在 < CHECKPOINT-END >记录中被引用
- < CHECKPOINT-END >：当检查点完成时。它包含 ATT + DPT，在写入< CHECKPOINT-BEGIN >日志记录时捕获

# ARIES Recovery
ARIES 协议由三个阶段组成。在崩溃后启动时，DBMS 将执行以下阶段：
1. Analysis：读取 WAL 以识别缓冲池中的脏页面和崩溃时的活动事务。在分析阶段结束时，ATT 会告诉 DBMS 崩溃时哪些事务处于活动状态。DPT 会告诉 DBMS 哪些脏页面可能没有存入磁盘
2. Redo：从日志中的适当点开始重复所有操作
3. Undo：逆转崩溃前未提交的事务的操作

## Analysis Phase
从通过数据库的主记录 LSN 找到的最后一个检查点开始 ：
1. 从检查点向前扫描日志
2. 如果数据库管理系统发现 TXN-END 记录，则将其事务从 ATT 移除
3. 所有其他记录，在 ATT 中添加状态为 UNDO 的事务，并在提交时将事务状态更改为 COMMIT。
4. 对于 UPDATE 日志记录，如果页 P 不在 DPT 中，则将 P 添加到 DPT 中，并将 P 的 recLSN 设置为日志记录的 LSN

## Redo Phase
此阶段的目标是让 DBMS 重复历史记录，重建崩溃前的状态。它将重新应用所有更新（甚至是中止的事务）并重做 CLR。

DBMS 从 DPT 中包含最小 recLSN 的日志记录开始向前扫描。对于具有给定 LSN 的每个更新日志记录或 CLR，DBMS 都会重新应用更新，除非
- 受影响页面不在 DPT 中
- 受影响页面位于 DPT 中，但该记录的 LSN 小于 DPT 中页面的 recLSN
- 受影响页面LSN（磁盘上） ≥ LSN

要重做一个操作，DBMS 重新应用日志记录中的更改，然后将受影响页面的 pageLSN 设置为该日志记录的 LSN

在重做阶段结束时，为状态为 COMMIT 的所有事务写入 TXN-END 日志记录，并将它们从 ATT 中删除

## Undo Phase
在最后一个阶段，DBMS 反转在崩溃时处于活动状态的所有事务。这些都是分析阶段之后 ATT 中具有 UNDO 状态的事务

DBMS 以反向 LSN 顺序处理事务，使用最后的 LSN 来加快遍历。当它反转事务的更新时，DBMS 会为 每次修改写入一个 CLR 条目到日志中

一旦成功终止了最后一个事务，DBMS 就会清空日志，然后准备开始处理新的事务