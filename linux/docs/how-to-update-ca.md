在Linux系统上更新本地证书（即更新根证书和信任证书）是确保系统能够正确验证SSL/TLS证书的一个重要步骤。不同的Linux发行版有不同的包管理器和路径来管理这些证书。以下是常见Linux发行版的证书更新方法：

### 1. Debian/Ubuntu

Debian和Ubuntu系统使用`ca-certificates`包来管理CA证书。

#### 更新证书包

首先，更新系统的包列表并升级`ca-certificates`包：

```bash
sudo apt update
sudo apt upgrade ca-certificates
```

#### 手动添加新证书

1. 将新证书复制到`/usr/local/share/ca-certificates/`目录。这个目录通常用于用户添加的证书。
2. 证书文件必须是以`.crt`结尾的文件，例如`my-custom-ca.crt`。
3. 运行以下命令来更新证书：

   ```bash
   sudo update-ca-certificates
   ```

   这将扫描`/usr/local/share/ca-certificates/`目录并更新`/etc/ssl/certs/`中的证书集合。

### 2. Red Hat/CentOS/Fedora

这些发行版使用`ca-certificates`和`certmonger`来管理证书。

#### 更新证书包

```bash
sudo yum update ca-certificates
```

或对于基于`dnf`的系统：

```bash
sudo dnf update ca-certificates
```

#### 手动添加新证书

1. 将新证书文件复制到`/etc/pki/ca-trust/source/anchors/`目录。文件名应以`.crt`结尾。
2. 更新证书存储：

   ```bash
   sudo update-ca-trust
   ```

   这将重新生成系统信任的证书集合。

### 3. openSUSE/SUSE

使用`ca-certificates`包和`update-ca-certificates`工具来管理证书。

#### 更新证书包

```bash
sudo zypper refresh
sudo zypper update ca-certificates
```

#### 手动添加新证书

1. 将新证书复制到`/usr/share/pki/trust/anchors/`目录。
2. 更新证书存储：

   ```bash
   sudo update-ca-certificates
   ```

### 4. Arch Linux

Arch Linux使用`ca-certificates-utils`包来管理证书。

#### 更新证书包

```bash
sudo pacman -Syu ca-certificates-utils
```

#### 手动添加新证书

1. 将新证书文件复制到`/etc/ca-certificates/trust-source/anchors/`目录。
2. 更新证书存储：

   ```bash
   sudo update-ca-certificates
   ```

### 验证更新

可以使用以下命令验证系统是否已正确识别新证书：

```bash
openssl s_client -connect example.com:443 -CApath /etc/ssl/certs/
```

将`example.com`替换为需要测试的域名。如果证书链验证成功，则输出中不会有错误信息。
