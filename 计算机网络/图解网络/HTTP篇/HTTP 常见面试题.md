# HTTP基本概念
## HTTP是什么
HTTP 是超文本传输协议，也就是**H**yper**T**ext **T**ransfer **P**rotocol。

将这个定义进行扩写，我们可以给出HTTP的一句话描述：**HTTP 是一个在计算机世界里专门在「两点」之间「传输」文字、图片、音频、视频等「超文本」数据的「约定和规范」。**

## HTTP 报文常见字段
![[Pasted image 20240119163317.png]]
HTTP报文常见形式如上，常见的字段如下：

### Host 字段
客户端发送请求时，用来指定服务器的域名，形式如下：
```
Host: www.A.com
```

### Content-Length 字段
服务器在返回数据时，会有 `Content-Length` 字段，表明本次回应的数据长度，形式如下：
```
Content-Length: 1000
```

另外，Content-Length配合回车符、换行符可用于解决TCP “粘包”的问题，具体看见另一篇[文章](https://xiaolincoding.com/network/3_tcp/tcp_stream.html)
### Connection 字段

