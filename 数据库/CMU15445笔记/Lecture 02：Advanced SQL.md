# 聚合（aggregation）
![[Pasted image 20231028134411.png]]
聚合就像是从一系列的元组中选出单个值进行返回，对应有五种基本聚合函数：求平均数、求最小值、求最大值、求数值总和、求数量总和

聚合函数基本只能用在select的输出列，如下：
![[Pasted image 20231028134757.png]]
DISTINCT字段用于去重
![[Pasted image 20231028134842.png]]

# GROUP BY
![[Pasted image 20231028135351.png]]
将一系列元组进行分组，然后在各个分组上使用GROUP BY函数

# HAVING
![[Pasted image 20231028135838.png]]
Having是一个过滤函数，用于将选好的分组进行过滤后进行输出。这里注意一个细节，既然是将选好的分组进行过滤，因而需要将该函数放到最后，同时这里也只能用AVG(s.gpa)，因为实际上这里还不知道select的列。

# STRING OPERATION
![[Pasted image 20231028140837.png]]
LIKE用于匹配字符串，其中 `%` 用于匹配任意数量的子串， `_` 用于匹配任意一个字符

除此以外还有其他字符串操控函数：SUBSTRING、UPPER、LOWER、CONCAT

# OUTPUT DIRECTION
![[Pasted image 20231028143757.png]]
MySQL这个指令比较常见

# OUTPUT CONTROL
## ORDER BY
![[Pasted image 20231028144137.png]]
其中ASC是升序，DESC是降序

## LIMIT
![[Pasted image 20231028144606.png]]
LIMIT 20 OFFSET 10相当于从第10个记录开始，返回20条记录

# NESTED QUERY（嵌套查询）
