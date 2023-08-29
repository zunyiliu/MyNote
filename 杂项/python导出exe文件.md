[网址](https://juejin.cn/post/6972510297441599518)
主要就是用pyinstaller来进行打包，其中比较重要的是如何将外部导入库一并导出为exe文件，这个博客中写到了要在pyinstaller命令中加上-p参数，并跟上我们的库文件地址。这个在pycharm中一般就有"E:\python项目\图片转移\venv\Lib\site-packages" 这样的文件地址

最后成品就类似于这个：pyinstaller -F -w main.py -p E:\python项目\图片转移\venv\Lib\site-packages

其中我们因为使用到了控制台进行输入输出操作，因而就得去掉-w参数，这个是用来不要显示控制台用的。