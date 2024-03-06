# IPv6报文格式
![[Pasted image 20231028104604.png]]
![[Pasted image 20231028104617.png]]
Next Header字段指示了上一层的协议类型，这里的逐层包装就是对不同协议的包装。

# IPv6地址
![[Pasted image 20231028104801.png]]
![[Pasted image 20231028104836.png]]

# IPv6地址分类
![[Pasted image 20231028104908.png]]

## IPv6单播地址
![[Pasted image 20231028105117.png]]

**关于接口标识的生成**
![[Pasted image 20231028105155.png]]
就是直接借用MAC地址，生成一个唯一的接口标识

**全球单播地址（GUA）**
![[Pasted image 20231028105353.png]]
可以看到这里的前缀2000::/3就标识了GUA

**唯一本地地址（ULA）**
![[Pasted image 20231028105518.png]]
这里使用FD00::/8标识ULA

**链路本地地址（LLA）**
![[Pasted image 20231028105804.png]]
这里使用FE80::/10标识LLA

## IPv6组播地址
**定义**
![[Pasted image 20231028110142.png]]

**被请求节点组播地址生成**
![[Pasted image 20231028110344.png]]
这我是没看懂的，保留最后24bit，不就是之前MAC地址的后24bit，又固定了104前缀，怎么做组播组的配置呢？

## IPv6任播地址
![[Pasted image 20231028110503.png]]
其实就是多个节点使用同一个地址，然后其他地址访问该地址时，会选择一个最近的节点进行访问。

# IPv6地址配置
![[Pasted image 20231028110917.png]]
链路本地地址遵循FE80::/10的前缀
全球单播地址遵循2000::/3的前缀
IPv6的环回地址只有::1这一个
被请求节点组播地址根据两个单播地址生成

## 配置过程
![[Pasted image 20231028112101.png]]
链路本地地址可以直接用EUI-64就能配置出来
全球单播地址配置可以通过DHCP或NDP

**地址配置**
![[Pasted image 20231028112217.png]]

**DAD**
![[Pasted image 20231028112444.png]]
![[Pasted image 20231028112510.png]]

**地址解析**
IPv6使用ICMPv6的NS和NA报文来取代ARP在IPv4中的地址解析功能

