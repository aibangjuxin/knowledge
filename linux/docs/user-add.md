# summary
Linux groudadd 命令的详细参考，比如参数-g -r 的解释，另外useradd的详细解释，比如参数-m -l -c -u -s -r 并且以markdown的格式帮我输出。这个需求是想要在Dockerfile中切换非root用户来执行的程序
Here are the explanations of groupadd and useradd commands in Markdown format:
## groupadd
The groupadd command creates a new group in Linux. Some useful options include:
- -g: Assigns the specified GROUPID number to the new group account. Must be a non-negative integer below 2147483648.  
- -r: Creates a system account. Creates a group with a User ID less than NEW_GID_MIN or greater than NEW_GID_MAX from login.defs.
For example:
groupadd -g 4000 developers  creates a new group named developers with GID 4000.
## useradd
The useradd command creates a new user in Linux. Some useful options include: 
- -m: Create the user's home directory and copy the files from the skeleton directory (/etc/skel).  
- -l: Don't create a group with the same name as the user, use the DEFAULT_GROUP.   
- -c: Comment for the user account. Usually the user's full name. 
- -u: Assigns the specified USERID number to the new user account. Must be a non-negative integer below 2147483648.  
- -s: The name of the user's login shell. The default is /bin/sh.  
- -r: Creates a system user. Creates a user with a User ID less than UID_MIN or greater than UID_MAX from login.defs. 
For example:
useradd -m -c "John Doe" -s /bin/bash john
creates a new user named john, with a comment of "John Doe", login shell of /bin/bash, and creates a home directory.
Using these commands with the -r flag is useful when creating system users in Docker containers

在Dockerfile中切换到非root用户来执行程序,需要注意以下几点:
## 定义非root用户
使用`USER`指令来指定运行镜像的用户。例如:
USER john   # 指定john用户
该用户必须是镜像内已存在的用户。可以使用`RUN useradd`等命令创建用户。
## 设置正确的文件权限
以非root用户运行前,需要确保文件和目录具有适当的权限。例如:
RUN chown -R john:john /some/directory  # 授予john用户目录访问权限
## 考虑安全隐患
以非root用户运行可以减小安全风险,但不意味着绝对安全。仍需谨慎编写Dockerfile及应用程序代码。特别是避免提升权限到root。
## 完整例子
下面是一个简单的例子:
dockerfile
# 创建john用户
RUN useradd john

# 将/app目录的拥有者改为john
RUN chown -R john:john /app

# 将工作目录切换到/app
WORKDIR /app

# 以john用户运行容器
USER john

# 运行python应用
CMD [ "python", "./app.py" ]
此镜像以john用户的权限运行python应用app.py。在构建和运行此镜像的过程中以及在最终容器内,都无法以root权限运行任何命令。这减小了安全风险,是Dockerfile的最佳实践


在 Dockerfile 中切换到非 root 用户来执行程序时，需要注意以下几点：

1. 确保需要运行的程序在非 root 用户权限下可以正常运行。
2. Docker 镜像中必须已经存在非 root 用户，或者在 Dockerfile 中先创建一个非 root 用户。
3. 在 Dockerfile 中通过 USER 指令设置切换到非 root 用户运行程序。

具体的实现方法如下：

1. 确保需要运行的程序在非 root 用户权限下可以正常运行。

在 Dockerfile 中创建用户并切换到该用户前，需要先在镜像中安装需要运行的程序，并确保该程序可以在非 root 用户权限下运行。否则程序可能会因为权限不足而无法正常运行。

1. Docker 镜像中必须已经存在非 root 用户，或者在 Dockerfile 中先创建一个非 root 用户。

在 Docker 中，可以通过 adduser 命令创建一个新的非 root 用户。例如：

RUN useradd -u 1000 -ms /bin/bash myuser

该命令会创建一个 UID 为 1000，shell 为 bash 的用户 myuser。

也可以使用 USER 命令指定一个现有的非 root 用户。例如：

USER myuser

该命令会切换到名为 myuser 的用户来执行后面的指令。

1. 在 Dockerfile 中通过 USER 指令设置切换到非 root 用户运行程序。

在 Dockerfile 中，使用 USER 指令指定切换到非 root 用户。例如：

USER myuser
CMD ["/path/to/myprogram"]

以上命令会在容器运行时切换到 myuser 用户，并执行 /path/to/myprogram 程序。

需要注意的是，使用非 root 用户运行程序可能会导致程序无法读写某些需要 root 权限的文件或目录。在这种情况下，需要手动指定对应文件或目录的权限或者修改 Docker 镜像中对应文件或目录的所有者或权限。
