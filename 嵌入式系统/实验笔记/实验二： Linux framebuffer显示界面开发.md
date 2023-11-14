本次实验需要我们进行显示界面的开发，具体需要编写的代码在`/common/graphic.c`中的`fb_draw_rect()`和`fb_draw_rect()`两个函数。

**fb_draw_rect()**
直接遍历整个矩形的点，给缓冲区赋值即可
```C
for(int i = x;i < x + w;i++)
        for(int j = y;j < y + h;j++)
            *(buf + j * SCREEN_WIDTH + i) = color;
```

关于缓冲区：
- 横轴为X轴，纵轴为Y轴
- 缓冲区和屏幕一一对应，X轴方向向右，Y轴方向向下，所以赋值是上面这种形式
![[Pasted image 20231114174307.png]]
- 边界值SCREEN_WIDTH和SCREEN_HEIGHT都不会取
- **逻辑上x1、y1是左下角，x2、y2是右上角**，实际上对应了左上角和右下角
