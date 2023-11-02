# WLAN工作原理
## CAPWAP协议
![[Pasted image 20231102095819.png]]
有点类似于控制平面，AC（Access Controler）负责集中控制所有的AP

**特点**
![[Pasted image 20231102095909.png]]


**CAPWAP隧道建立**
![[Pasted image 20231102095954.png]]
1. DHCP交互：AP获取IP地址
2. 发现阶段：AP通过Discovery发现AC
3. DTLS链接：这个阶段可以选择CAPWAP隧道是否采用DTLS加密传输UDP报文
4. Join阶段：AP请求在AC上线
5. Image Data阶段：AP根据协商判断当前版本是否为最新版本。如果不是，AP向AC请求下载最新版本，然后在隧道上更新软件版本
6. Config & Data Check阶段： ![[Pasted image 20231102100838.png]]
7. Run阶段：Keepalive是数据心跳报文，Echo是控制心跳报文。此时AP已经上线
8. 配置下发阶段：AP上线后，会主动向AC发送Configuration Status Request报文，该信息中包含了现 有AP的配置，为了做AP的现有配置和AC设定配置的匹配检查。

## WLAN关键报文
![[Pasted image 20231102101216.png]]

![[Pasted image 20231102101338.png]]
![[Pasted image 20231102101345.png]]

## STA（站点）上线
![[Pasted image 20231102101502.png]]

**扫描**
- 主动扫描：客户端发送Probe Request帧（探测请求帧），获取可使用的无线服务
- 被动扫描：STA被动接收AP发送的Beacon帧

**认证**
![[Pasted image 20231102103956.png]]

**关联**
![[Pasted image 20231102104015.png]]

