# Tcpdump 使用指南与实战案例 (Explorer Tcpdump)

`tcpdump` 是 Linux 系统中功能最强大的网络抓包与分析工具。它基于 `libpcap` 库，能够捕获并过滤网络数据包，是网络排障、安全审计和协议分析的必备神器。

---

## 1. 核心基础选项

| 选项 | 说明 | 建议 |
| :--- | :--- | :--- |
| `-i [interface]` | 指定抓包网卡 (如 `eth0`, `any`) | 使用 `any` 可监控所有网卡 |
| `-n` | 不解析域名 (直接显示 IP) | **必选**，显著提升性能 |
| `-nn` | 不解析端口号 (直接显示数字) | **必选**，避免 DNS 调用干扰 |
| `-c [count]` | 捕获指定数量的数据包后停止 | 测试时建议设置，防止刷屏 |
| `-v, -vv, -vvv` | 增加输出详细程度 | 调试复杂协议时使用 |
| `-w [file].pcap` | 将抓取的内容写入文件 | 便于后续用 Wireshark 分析 |
| `-r [file].pcap` | 从文件中读取并显示内容 | |
| `-s 0` | 抓取完整数据包 (Snapshot Length) | 默认可能只抓部分，全量分析必选 |

---

## 2. BPF 过滤表达式 (BPF Filter)

`tcpdump` 的强大源于其灵活的过滤语法。

### 2.1 基于方向与类型
*   **Host 过滤**: `tcpdump host 192.168.1.1` (监控该 IP 的进出流量)
*   **Src/Dst 过滤**: `tcpdump src 1.1.1.1` 或 `tcpdump dst port 80`
*   **Network 过滤**: `tcpdump net 192.168.1.0/24`
*   **Port 过滤**: `tcpdump port 443` 或 `tcpdump portrange 1024-5000`

### 2.2 逻辑组合
使用 `and` (&&), `or` (||), `not` (!) 进行组合：
```bash
# 抓取来自 192.168.1.100 且 端口是 80 或 443 的包
tcpdump -i eth0 'src host 192.168.1.100 and (port 80 or port 443)'
```

---

## 3. 实战案例场景

### 3.1 观察数据包原始内容 (ASCII/Hex)
如果您想看 HTTP Header 或 Payload：
```bash
# -A: 以 ASCII 打印 (方便看 HTTP 内容)
# -X: 同时显示 Hex 和 ASCII
sudo tcpdump -i eth0 -AnS port 80
```

### 3.2 过滤特定 TCP 状态 (Flag 过滤)
在排查连接超时或三次握手失败时非常有效：
```bash
# 只抓 SYN 包 (连接发起)
sudo tcpdump 'tcp[tcpflags] & (tcp-syn) != 0'

# 只抓 RST 包 (异常断开)
sudo tcpdump 'tcp[tcpflags] & (tcp-rst) != 0'

# 结合逻辑，抓取非 ACK 且带 SYN 的包
sudo tcpdump 'tcp[13] & 18 == 2'
```

### 3.3 监控 ICMP (Ping) 流量
```bash
# 抓取所有 ICMP 请求与应答
sudo tcpdump -i any icmp
```

### 3.4 远程抓包并本地 Wireshark 实时查看
```bash
ssh user@remote_host 'tcpdump -s 0 -U -n -w - not port 22' | wireshark -k -i -
```

---

## 4. 进阶过滤技巧 (按协议字段)

`tcpdump` 支持直接指定协议偏移量进行深度匹配：

*   **IP 分片标志位**: `ip[6] & 32 != 0`
*   **TCP Payload 长度 > 0**: `tcp[((tcp[12:1] & 0xf0) >> 2):4] > 0`
*   **HTTP GET 请求**: `tcp[((tcp[12:1] & 0xf0) >> 2):4] = 0x47455420` (匹配 "GET ")

---

## 5. 最佳实践建议

1.  **性能优先**: 在高并发环境下，务必使用 `-n` 和 `-nn`。
2.  **Snapshot Length**: 如果不需要看具体内容只看报文交互，不设置 `-s`；如果需要深度分析 Payload，务必设置 `-s 0`。
3.  **缓冲区覆盖**: 如果抓包频率极高，配合 `-B [buffer_size]` 增加内核缓冲区大小防止丢包。
4.  **文件切分**: 使用 `-C [file_size]` 和 `-W [number]` 实现循环抓包，防止磁盘被撑爆。
    ```bash
    # 每个文件 100MB，最多保留 10 个文件
    sudo tcpdump -i eth0 -C 100 -W 10 -w traffic.pcap
    ```

---

> [!TIP]
> **快速查阅**: 
> *   `man tcpdump`: 官方最全文档。
> *   `tcpdump -D`: 查看当前系统支持的所有网卡。
