## 在 Linux 中更改 MTU 大小

在 Linux 上更改 MTU（最大传输单元）大小主要有两种方法：

**1. 使用 `ip` 命令（推荐）：**

`ip` 命令是现代 Linux 发行版中管理网络接口的推荐方式。以下是使用方法：

```
sudo ip link set dev <interface_name> mtu <new_mtu_size>
```

**请替换以下内容：**

* `<interface_name>`：这是您的网络接口名称。您可以使用 `ip addr show` 命令找到它。查找您要修改的接口（例如 `eth0`、`enp3s0`）。
* `<new_mtu_size>`：这是您要设置的新 MTU 大小。典型的标准 MTU 是 1500 字节，但可以根据您的网络配置进行调整。

**示例：**

```
sudo ip link set dev eth0 mtu 9000
```

此命令将 `eth0` 接口的 MTU 大小设置为 9000 字节。

**2. 使用 `ifconfig` 命令（较旧系统）：**

`ifconfig` 命令是一种较旧的方法，在某些系统上可能已弃用。仅当 `ip` 命令不可用时才使用它。以下是语法：

```
sudo ifconfig <interface_name> mtu <new_mtu_size>
```

**两种方法的解释：**

* `sudo`: 授予 root 权限以执行命令。
* `ip link set dev`: 命令的这一部分（对于 `ip`）指定您正在修改网络设备的链路设置。
* `ifconfig`: 此命令直接配置网络接口。
* `<interface_name>`：如前所述，这是您的网络接口名称。
* `mtu`: 此关键字指定您正在设置 MTU 大小。
* `<new_mtu_size>`:  以字节为单位的所需新 MTU 大小。

**使更改永久生效（可选）：**

使用上述命令进行的更改是临时的，将在重新启动后恢复。要使更改永久生效，您需要修改网络接口配置文件。具体方法取决于您的 Linux 发行版。以下两种方法很常见：

* **对于 systemd-networkd（常见于较新的发行版）：**

  1. 编辑位于 `/etc/systemd/network/` 中的适当网络配置文件（例如 `00-wan.network`）。
  2. 在相关接口配置块中添加一行 `MTU=<new_mtu_size>`。
  3. 保存文件并使用 `sudo systemctl restart systemd-networkd` 重新启动网络服务。

* **对于由 DHCP 管理的接口：**

  1. 编辑 DHCP 客户端配置文件，通常位于 `/etc/dhcp/dhclient.conf`。
  2. 为特定接口添加一行 `supersede interface-mtu <new_mtu_size>`。
  3. 保存文件并使用适用于您的发行版的相应命令重新启动 DHCP 客户端服务（例如 `sudo systemctl restart dhcpcd`）。

**重要注意事项：**

* 在网络路径上设置超过最大支持大小的 MTU 大小会导致数据包碎片化和性能问题。确保所有网络设备之间的兼容性至关重要。
* 更改 MTU 大小可能需要对依赖于先前设置的其他系统或应用程序进行调整。
* 建议在将 MTU 大小更改为永久设置之前测试其对网络性能的影响。


There are two main approaches to changing the MTU (Maximum Transmission Unit) size on Linux:

**1. Using the `ip` command (recommended):**

The `ip` command is the recommended way to manage network interfaces in modern Linux distributions. Here's how to use it:

```
sudo ip link set dev <interface_name> mtu <new_mtu_size>
```

**Replace the following:**

* `<interface_name>`:  This is the name of your network interface. You can find this using the `ip addr show` command. Look for the interface you want to modify (e.g., `eth0`, `enp3s0`).
* `<new_mtu_size>`: This is the new MTU size you want to set. The typical standard MTU is 1500 bytes, but it can be adjusted based on your network configuration.

**Example:**

```
sudo ip link set dev eth0 mtu 9000
```

This command sets the MTU size of the `eth0` interface to 9000 bytes.

**2. Using the `ifconfig` command (older systems):**

The `ifconfig` command is an older method and might be deprecated on some systems. Use it only if the `ip` command is unavailable. Here's the syntax:

```
sudo ifconfig <interface_name> mtu <new_mtu_size>
```

**Explanation for both methods:**

* `sudo`: Grants root privileges to execute the command.
* `ip link set dev`: This part of the command (for `ip`) specifies that you're modifying the link settings of a network device.
* `ifconfig`: This command directly configures the network interface.
* `<interface_name>`: As mentioned earlier, this is the name of your network interface.
* `mtu`: This keyword specifies that you're setting the MTU size.
* `<new_mtu_size>`: The desired new MTU size in bytes.

**Making the change permanent (optional):**

The changes made using the above commands are temporary and will revert after a reboot. To make the change permanent, you'll need to modify your network interface configuration file. The specific method depends on your Linux distribution. Here are two common approaches:

* **For systemd-networkd (common in newer distributions):**

  1. Edit the appropriate network configuration file located in `/etc/systemd/network/` (e.g., `00-wan.network`).
  2. Add a line like `MTU=<new_mtu_size>` within the relevant interface configuration block.
  3. Save the file and restart the network service using `sudo systemctl restart systemd-networkd`.

* **For interfaces managed by DHCP:**

  1. Edit the DHCP client configuration file, typically located at `/etc/dhcp/dhclient.conf`.
  2. Add a line like `supersede interface-mtu <new_mtu_size>` for the specific interface.
  3. Save the file and restart the DHCP client service using the appropriate command for your distribution (e.g., `sudo systemctl restart dhcpcd`).

**Important considerations:**

* Setting an MTU size larger than the maximum supported size on your network path can lead to packet fragmentation and performance issues. It's crucial to ensure compatibility between all devices on the network.
* Changing the MTU size might require adjustments on other systems or applications that rely on the previous setting.
* It's recommended to test the impact of a new MTU size on your network performance before making it permanent.

