# 概述
- 类的本质就是语法糖，用于将变量和方法（函数）组织在一起
- 类的使用可以让代码简洁，提高代码的可复用性
- 类成员分为public和private，其中private变量只能被类内部的方法使用

# class和struct的区别
- 从技术上讲，class默认为private，struct默认为public，其他没有任何区别
- 从历史上讲，struct是C的东西，C++是为了向后兼容才保留了struct
- 从使用上讲，struct通常只作为变量的集合，不会用于复杂的处理，也不会用于继承
- 从使用上讲，class才是C++用于面向对象编程的方式

