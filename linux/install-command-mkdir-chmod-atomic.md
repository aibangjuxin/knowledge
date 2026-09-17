# 一行 install,搞定 mkdir + chmod 拼接的"中间态"灾难

---

我前两天翻一个老脚本,看见一行:

```bash
install -d -m 0700 /tmp/cert
```

愣了两秒。`install`?这货不是装软件的吗?

查完 man 才发现——**它才是 Linux/Unix 上写"建目录+设权限"的正确姿势**。之前我们一直在用的 `mkdir -p && chmod 0700`,其实是个藏着 race condition 的"两步走"。

今天这篇就讲清楚三件事:

- `install -d` 是什么、能干什么
- 它跟 `mkdir + chmod` 到底差在哪
- 什么时候用、什么时候别用

---

## 一、先认识 install

`install` 是 BSD/GNU coreutils 里都有的命令,名字虽然叫"install",其实干四件事:

- 复制文件(`install src dst`)
- 创建目录(`install -d dir`)
- 改变属主/权限(配合 `-o` `-g` `-m`)
- 软链/硬链(配合 `-l`)

man 第一句就写了:**install – install binaries**。它原本是为 make install 这种场景设计的——把编译产物"装"到目标路径,同时带上正确的权限和属主。

**我们今天只讲它的目录创建能力**:`install -d`。

它最常见的形态就三种:

```bash
# 1. 单纯建目录(递归建父目录,等价 mkdir -p)
install -d /tmp/cert

# 2. 建目录 + 设权限(一步到位)
install -d -m 0700 /tmp/cert

# 3. 建目录 + 改属主(需要 root)
sudo install -d -m 0755 -o www -g www /var/www/app
```

**注意 `-d` 这个 flag**——它的全称是 `--directory`,告诉 install "我要建的不是文件,是目录"。

---

## 二、跟 mkdir + chmod 比,差在哪?

直接上对比表:

| 维度 | `mkdir -p && chmod 0700` | `install -d -m 0700` |
|---|---|---|
| **行数** | 2 行 | 1 行 |
| **系统调用次数** | mkdir(2) + chmod(2) | mkdir(2)(带 mode) |
| **父目录自动建** | ✅ `-p` | ✅ 默认就是 `-p` 行为 |
| **中间态窗口** | ⚠️ 有(0~几百 ms) | ✅ 没有 |
| **可移植性** | GNU/BSD 都一样 | BSD/GNU 略有 flag 差异 |
| **默认权限** | `0777 & ~umask` | `0755`(可被 `-m` 覆盖) |
| **Makefile 友好** | 一般 | ✅ 设计就是给 make install 用的 |

关键差别就是中间态那一行——也就是我们下一个 section 的重点。

---

## 三、那个"中间态"到底是什么?

假设你在 CI 脚本里写:

```bash
mkdir -p /tmp/cert
chmod 0700 /tmp/cert
```

这两行之间,有一个**时间窗口**——`/tmp/cert` 已经存在,但权限还是 `0755`(或者 umask 给的默认值)。

在 CI 这种高频并发场景下,这个窗口小到几毫秒;但对攻击者来说,**只要有别的进程在同一窗口读这个目录,就是一次信息泄露/权限提升的机会**。

我拿一个真实场景举例:**生成自签名证书的脚本**。

```bash
#!/bin/bash
# 传统写法(有中间态)
mkdir -p /tmp/cert
chmod 0700 /tmp/cert
# 此时 /tmp/cert 已经是 0755 了
openssl req -x509 -newkey rsa:4096 -keyout /tmp/cert/key.pem -out /tmp/cert/cert.pem
```

如果另一个用户在那个 5ms 的窗口里 `ls -la /tmp/cert`,就能看到 key.pem——但权限还没收紧,读不了。再过 5ms 权限收紧,但 key 文件已经生成了。

**更危险的是容器场景**——同一个宿主机上跑几百个并发 job,所有 job 都在 `/tmp/cert` 里建私钥,中间态窗口里另一个 job 的用户可能直接读到。

`install -d -m 0700` 的修法:

```bash
#!/bin/bash
# 一行修掉
install -d -m 0700 /tmp/cert
# 此时 /tmp/cert 已经是 0700 了,不存在中间态
openssl req -x509 -newkey rsa:4096 -keyout /tmp/cert/key.pem -out /tmp/cert/cert.pem
```

**为什么 `install` 没中间态?** 因为它底层只调一次 `mkdir(2)`,并且把 mode 作为参数一起传进去。`mkdir(2)` 的 man 页写得很清楚:

> The mode of the new directory is determined by the mode argument. ... the directory is created with this mode, modified by the process's umask.

也就是说,**目录一诞生就是目标 mode**,没有任何过渡态。

---

## 四、三个最实用的写法

### 4.1 临时目录(最常用)

```bash
# CI 跑测试用的临时目录,跑完销毁
install -d -m 0700 /tmp/ci-runner-$$
```

### 4.2 应用数据目录

```bash
# 给 systemd 服务建数据目录,属主是 app 用户
sudo install -d -m 0750 -o app -g app /var/lib/myapp
```

`-m 0750` 而不是 `0755`:只有 owner 和 group 能进,其他人连列目录都不行——这是给服务账号用的标准权限。

### 4.3 部署脚本里的目录树

```bash
# Makefile / 部署脚本里一次建多级
install -d -m 0750 \
  /opt/myapp/bin \
  /opt/myapp/etc \
  /opt/myapp/var/log \
  /opt/myapp/var/run
```

**多目录一次建**——这点比 `mkdir -p a b c` 还干净,因为 `mkdir -p` 多个参数时,每个目录独立调一次 syscall,而 `install -d` 在 BSD 实现里会做更智能的批处理。

---

## 五、三个不太常用但很有用的 flag

### 5.1 `-D destdir`:前缀重定向

```bash
# RPM/Deb 打包时把目录建到 staging 区
install -d -m 0755 -D /tmp/staging/usr/local/bin
```

`-D` 是 BSD 专属,**GNU coreutils 没有**——它会把所有路径加个前缀 `/tmp/staging`。这在做 `.deb` 包的时候特别有用,你可以把所有东西装到一个临时目录,然后 `tar` 起来。

### 5.2 `-o owner` / `-g group`:改属主

```bash
sudo install -d -m 0750 -o nginx -g nginx /var/log/nginx
```

Linux 上等价于 `mkdir && chown`,但**少一次 syscall**。

### 5.3 `-l linkflags`:不复制,只链接

```bash
# 软链(而不是复制)
install -l s -m 0755 /usr/local/bin/python3 /usr/local/bin/python
```

这一条比较进阶,日常用得不多,但在搞 symlink farm(比如 alternatives 系统)的时候是真香。

---

## 六、什么时候**别**用 install -d?

不是所有场景都适合。下面三种情况,**老老实实用 mkdir**:

### 6.1 跨 shell 兼容 / 教学场景

`install -d` 是 BSD/GNU 都有的,但**某些 BusyBox 嵌入式环境**裁剪了。教学场景里,`mkdir -p` 是更"标准"的答案。

### 6.2 需要保留特定 mode 语义

`install -d` 的默认 mode 是 `0755`(可被 `-m` 覆盖)。`mkdir` 的默认是 `0777 & ~umask`,跟 umask 联动更紧密。

如果你**故意要靠 umask 控权限**(比如 root 用户的 umask 是 0027),`mkdir` 会自动应用,但 `install -d` 必须显式给 `-m`,不然就是 `0755` 写到石头上。

### 6.3 Bash 内建 / POSIX 严格要求

POSIX 标准里**没有 `install` 命令**——它属于"通用工具但非强制"。如果你的脚本要在 `/bin/sh` 这种纯 POSIX 环境跑,只能 `mkdir`。

---

## 七、对比看一眼:三个建目录的命令

```bash
# 写法 1:mkdir(最常见)
mkdir -p /tmp/cert && chmod 0700 /tmp/cert

# 写法 2:install(今天的主角)
install -d -m 0700 /tmp/cert

# 写法 3:mkdir 直接带 mode(很多人不知道)
mkdir -m 0700 -p /tmp/cert
```

`写法 3` 你可能没见过——其实 `mkdir` 也支持 `-m`,而且和 `install -d` 一样,只调一次 syscall,没有中间态。

**那为啥还要 `install`?**

| 场景 | 推荐 |
|---|---|
| CI 脚本 / Makefile | `install -d -m ...` |
| Makefile 的 install target | `install -d`(设计就是给这个用的) |
| 临时脚本 / 教学 | `mkdir -m ... -p` 即可 |
| POSIX 严格脚本 | `mkdir -p && chmod` |

---

## 八、一句话总结

**`install -d -m 0700` 是"建目录+设权限"的原子操作。** 比 `mkdir + chmod` 少一次 syscall、零中间态、Makefile 友好——这是 Unix 老炮儿们一直用的写法,只是现代教程很少讲。

下一篇我会写"`umask` 到底是什么鬼——为什么我新建的文件总是 0644"——把权限这套彻底讲透。

---

*我是 Lex,K8s 工程师 / 家里跑 AI Agent 的人。*
