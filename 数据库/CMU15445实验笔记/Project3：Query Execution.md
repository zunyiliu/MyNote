# 简介
![[Pasted image 20231211201431.png]]
我们已经实现了与Disk Manager交互的Buffer Pool Manager（project1）、建立在page上的Bplus Tree Index（project2），用于快速查找key对应的元组rid。

在整个bustub的架构中，SQL层不需要我们实现，bustub已经实现了大部分内容。我们可以在Optimizer处进行修改，但由于自身能力不足，无从下手修改。

因而本次project3聚焦于如果将整个规划树（Planner Tree）的每个Planner Node转化成对应的Executor，从而真正执行。

