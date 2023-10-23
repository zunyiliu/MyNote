# 课程概述
## 课程资源
- [课程主页2022Fall](https://15445.courses.cs.cmu.edu/fall2022/schedule.html)
- [实验AC代码](https://github.com/ejunjsh/bustub)
- [实验博客](https://ceyewan.top/archives/page/2/)
- [Lab0翻译](http://webtrans.yodao.com/webTransPc/index.html#/?url=https%3A%2F%2F15445.courses.cs.cmu.edu%2Ffall2022%2Fproject0%2F&from=auto&to=auto&type=1)

## 课程学习
每次看视频前先将本节课ppt看完，然后看视频，然后跟着ppt把笔记重新做一遍。

# 关系模型
## 关系模型的优势
- 以简单的数据结构（关系）存储数据库。
- 物理存储由 DBMS 实现。
- 通过高级语言访问数据，数据库管理系统找出最佳执行策略。

## 什么是关系
关系是一个无序集合，包含代表实体（entity）的属性关系。

元组是关系中的一组属性值（也称为其域）
- 属性值都是原子/不可分的
- NULL也是一种属性值

所以可以把关系简单理解为一张表，表头就是属性，每一行都是一个元组/实体。
![[Pasted image 20231023163542.png]]

## 主键与外键
关系的**主键**唯一标识一个元组。

如果表没有定义内部主键，有些 DBMS 会自动创建内部主键。
![[Pasted image 20231023163744.png]]

**外键**指定一个关系中的属性必须映射到另一个关系中的元组。
![[Pasted image 20231023164137.png]]

## 关系代数
这一部分不再赘述，也没什么好讲的

注：关系模型与实现语言无关，最常使用的就是SQL。