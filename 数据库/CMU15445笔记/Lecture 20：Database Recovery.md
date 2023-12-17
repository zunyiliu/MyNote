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

