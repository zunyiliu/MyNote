# Large files
本任务实际上就是要我们修改函数`bmap()`，原XV6的inode能够存储的数据量是（256+12）个data块，现在需要我们进行扩展，将一个直接块改造为二级间接块，这样能够存储的数据量就达到（256 * 256 + 256 + 11）。

主要代码如下：
```C
else if(bn < NINDIRECT * NINDIRECT + NINDIRECT){  
    bn -= NINDIRECT;  
    if((addr = ip->addrs[12]) == 0)  
        ip->addrs[12] = addr = balloc(ip->dev);  
    bp = bread(ip->dev,addr);  
    a = (uint*)bp->data;  
    //这里获得二级间接块  
    if(a[bn / NINDIRECT] == 0){  
        a[bn / NINDIRECT] = balloc(ip->dev);  
        log_write(bp);  
    }  
    brelse(bp);  
    //这里获得一级间接块  
    bp = bread(ip->dev,a[bn / NINDIRECT]);  
    a = (uint*)bp->data;  
    if(a[bn % NINDIRECT] == 0){  
        a[bn % NINDIRECT] = balloc(ip->dev);  
        log_write(bp);  
    }  
    brelse(bp);  
    return a[bn % NINDIRECT];  
}
```
1. 先获得在二级间接块内的偏移块bn。
2. 读取最高一级间接块，判断是否为空，为空就分配
3. 读取二级间接块，这里采用bn / NINDIRECT，就能表示为在哪一个二级间接块中。
4. 记得释放最高一级间接块
5. 读取一级间接块，这里采用bn % NINDIRECT，就能表示为二级间接块中的偏移块。
6. 返回块号

同时我们还需要在`itrunc()`函数中修改，确保释放所有的块
```C
if(ip->addrs[12]){  
    bp = bread(ip->dev,ip->addrs[12]);  
    a = (uint*)bp->data;  
    for(int i = 0;i < NINDIRECT;i++)  
        if(a[i]) {  
            struct buf *tmp = bread(ip->dev,a[i]);  
            uint *b = (uint*)tmp->data;  
            for (int j = 0; j < NINDIRECT; j++)  
                if(b[j])  
                    bfree(ip->dev,b[j]);  
            brelse(tmp);  
            bfree(ip->dev,a[i]);  
            a[i] = 0;  
        }  
    brelse(bp);  
    bfree(ip->dev,ip->addrs[12]);  
    ip->addrs[12] = 0;  
}
```

# Symbolic links
本节任务涉及到软链接的概念，关于硬链接和软链接，可以直接看这个[博客](https://blog.csdn.net/weixin_44966641/article/details/120582103?spm=1001.2014.3001.5502)
可以简单理解为，硬链接就是别名，软链接是跳转提示。

我们需要实现一个新的系统调用`symlink(char *target, char *path)`，用于在path处创建一个软链接，相当于是从path到target的跳转提示。

代码如下：
```C
uint64  
sys_symlink(void)  
{  
    struct inode* ip;  
    char target[MAXPATH],path[MAXPATH];  
    if(argstr(0,target,MAXPATH) < 0 || argstr(1,path,MAXPATH) < 0)  
        return -1;  
  
    begin_op();  
    ip = create(path,T_SYMLINK,0,0);  
    if(ip == 0){  
        end_op();  
        return -1;  
    }  
    if(writei(ip,0,(uint64)target,0,MAXPATH) < MAXPATH){  
        iunlockput(ip);  
        end_op();  
        return -1;  
    }  
  
    iunlockput(ip);  
    end_op();  
    return 0;  
}
```
1. 读取target和path
2. 在path处创建一个类型为T_SYMLINK的inode
3. 向该inode写入target，表示为跳转提示
4. 返回0，表示成功

除此以外，我们还需要修改sys_open，使得可以打开一个T_SYMLINK类型的文件，并递归跳转。
```C
...
if(ip->type == T_SYMLINK && !(omode & O_NOFOLLOW)){  
    for(int i = 0;i < 10;i++){  
        if(readi(ip,0,(uint64)path,0,MAXPATH) < MAXPATH){  
            iunlockput(ip);  
            end_op();  
            return -1;  
        }  
        iunlockput(ip);  
        ip = namei(path);  
        if(ip == 0){  
            end_op();  
            return -1;  
        }  
        ilock(ip);  
        if(ip->type != T_SYMLINK)  
            break;  
    }  
    if(ip->type == T_SYMLINK){  
        iunlockput(ip);  
        end_op();  
        return -1;  
    }  
}
...
```
这里实际上就是读取inode，判断是否是T_SYMLINK，如果是就递归查找该跳转提示（利用namei函数）。同时要设置最大跳转次数为10，方式循环跳转。

