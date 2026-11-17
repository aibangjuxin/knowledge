在Linux环境下，有多种方法可以让你的Shell脚本在后台运行，即使在重新连接服务器时仍然可以查看脚本的执行情况。以下是一些常用的解决方案：

1. **使用`nohup`命令**：`nohup`命令可以让你在后台运行脚本，即使关闭终端或断开连接，脚本仍然会继续运行。使用`nohup`的基本语法如下[14]：

```bash
nohup your_script.sh &
```

2. **使用`screen`命令**：`screen`是一个终端多路复用器，允许你在一个物理终端上创建多个虚拟终端。你可以在`screen`会话中运行脚本，然后在需要时重新连接到该会话。以下是使用`screen`的基本步骤[15]：

```bash
screen -S your_session_name  # 创建一个名为your_session_name的screen会话
./your_script.sh             # 在screen会话中运行脚本
Ctrl + A, D                  # 分离screen会话，使其在后台运行
```

要重新连接到screen会话，可以使用以下命令：

```bash
screen -r your_session_name
```

3. **使用`tmux`命令**：`tmux`是另一个终端多路复用器，类似于`screen`。你可以在`tmux`会话中运行脚本，并在需要时重新连接到该会话。以下是使用`tmux`的基本步骤[8]：

```bash
tmux new-session -s your_session_name  # 创建一个名为your_session_name的tmux会话
./your_script.sh                        # 在tmux会话中运行脚本
Ctrl + B, D                             # 分离tmux会话，使其在后台运行
```

要重新连接到tmux会话，可以使用以下命令：

```bash
tmux attach-session -t your_session_name
```

这些方法可以确保你的脚本在后台持续运行，即使在重新连接服务器时仍然可以查看脚本的执行情况。

Citations:
[1] https://blog.csdn.net/napolunyishi/article/details/25147251
[2] https://blog.csdn.net/qq_52852138/article/details/124309066
[3] https://www.xxshell.com/1778.html
[4] https://cloud.tencent.com/developer/article/1659864
[5] https://blog.51cto.com/01wang/1643454
[6] https://www.cnblogs.com/FLY_DREAM/p/13881674.html
[7] http://ituibar.com/linux-command-screen-create-a-new-session-save-and-exit-the-current-session
[8] https://heibaimeng.com/post/121
[9] https://blog.csdn.net/weixin_33713707/article/details/86329792
[10] https://blog.csdn.net/weixin_40123451/article/details/108891448
[11] https://blog.csdn.net/weixin_42551260/article/details/117285007
[12] https://blog.csdn.net/daxiang10m/article/details/106440226
[13] https://www.cijiyun.com/newsview?id=67599
[14] http://www.runoob.com/linux/linux-comm-nohup.html
[15] https://andblog.cn/758
[16] https://cloud.tencent.com/developer/article/1019718?areaId=106001
[17] https://theresevoyer.com/use-nohup-execute-commands-background-keep-running-exit-shell-promt/
[18] https://blog.csdn.net/aaaaaab_/article/details/86717500
[19] https://juejin.cn/s/shell%E6%89%A7%E8%A1%8C%E5%91%BD%E4%BB%A4%E8%B6%85%E6%97%B6%E8%87%AA%E5%8A%A8%E7%BB%88%E6%AD%A2
[20] https://www.cnblogs.com/atuotuo/p/13601382.html
[21] https://blog.51cto.com/xfxuezhang/5859076
[22] https://www.cnblogs.com/goodcitizen/p/improve_efficient_of_shell_script_for_fetching_log_by_using_parallel_ssh.html
[23] https://www.jinjun.top/408.html
[24] https://nscc.mrzhenggang.com/screen/
[25] https://gnu-linux.readthedocs.io/zh/latest/Chapter06/sshBackstage.html
