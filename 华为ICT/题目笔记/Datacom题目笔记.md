# 广域网PPP
![[Pasted image 20231106194242.png]]
![[Pasted image 20231106194225.png]]
![[Pasted image 20231106194235.png]]
# ACL
![[Pasted image 20231106200550.png]]

![[Pasted image 20231106200644.png]]
# VLAN
VLAN ID取值范围为1-4095

VLAN 1为管理VLAN，可以在不配置Trunk接口的情况下在Trunk链路上传输

# STP
STP桥优先级只能设置为0-65535中的16个优先级，均为4096的倍数，分别为0, 4096, 8192, 12288, 16384, 20480, 24576, 28672, 32768, 36864, 40960, 45056, 49152, 53248, 57344, 61440

STP的5种状态：Forwarding、Learning、Listening、Blocking、Disabled
RSTP的3种状态：Discarding、Learning、Forwarding

![[Pasted image 20231106200729.png]]

# MPLS
标签总长度为4Byte

# OSPF
DR other路由器之间的邻居状态为2-way，只有和DR和BDR路由器之间的邻居状态才为Full。

OSPF邻居表：
```
OSPF Process 1 with Router ID 1.1.1.1 ：本地 OSPF 进程号为 1 与本端 OSPF Router ID 为 1.1.1.1
Router ID ：邻居 OSPF 路由器 ID
Address ：邻居接口地址
GR State ：使能 OSPF GR 功能后显示 GR 的状态（ GR 为优化功能），默认为 Normal
State ：邻居状态，正常情况下 LSDB 同步完成之后，稳定停留状态为 Full
Mode ：用于标识本台设备在链路状态信息交互过程中的角色是 Master 还是 Slave
Priority ：用于标识邻居路由器的优先级（该优先级用于后续 DR 角色选举）
DR ：指定路由器
BDR ：备份指定路由器
MTU ：邻居接口的 MTU 值
Retrans timer interval ：重传 LSA 的时间间隔，单位为秒
Authentication Sequence ：认证序列号
```

OSPF采用HELLO维持邻居关系

# VRP
![[Pasted image 20231106194922.png]]

![[Pasted image 20231106194326.png]]
# 以太网
以太网帧总长度范围：64-1518，去掉前导码等字段的长度为：46-1500

# CAPWAP
CAPWAP是基于UDP的

CAPWAP的两种隧道：数据隧道、管理隧道

