# macOS APP 网络域名观察脚本

脚本位置：

```bash
/Users/lex/git/knowledge/macos/scripts/app_network_observer.py
```

核心目标：

- 观察某个 APP 启动或运行后连接了哪些远程 IP、端口
- 尽量把 IP 关联回 DNS 域名
- 输出实时连接事件和最终频率统计
- 保存 JSONL 明细日志，方便后续 grep、jq、导入分析

## 推荐用法

观察并启动 Safari，抓 60 秒 DNS 和连接：

```bash
cd /Users/lex/git/knowledge
sudo ./macos/scripts/app_network_observer.py \
  --app Safari \
  --launch-app Safari \
  --dns \
  --duration 60
```

观察已经运行的进程：

```bash
./macos/scripts/app_network_observer.py --pid 12345 --duration 60
```

按进程参数模糊匹配，例如 Chrome：

```bash
sudo ./macos/scripts/app_network_observer.py \
  --match "Google Chrome" \
  --dns \
  --duration 120
```

按 bundle identifier 匹配：

```bash
sudo ./macos/scripts/app_network_observer.py \
  --bundle-id com.apple.Safari \
  --launch-bundle com.apple.Safari \
  --dns \
  --duration 60
```

如果不想 sudo，可以只看 APP 的连接 IP，并用 PTR 反查做弱域名补充：

```bash
./macos/scripts/app_network_observer.py \
  --app Safari \
  --reverse-dns \
  --duration 60
```

## 输出内容

实时输出类似：

```text
[2026-05-02T10:00:00+08:00] Safari:12345 TCP www.apple.com 17.253.144.10:443 ESTABLISHED apple/https
```

结束后会给出：

- Top domains
- Top remote IPs
- Top ports
- Top categories
- Top DNS queries
- Unresolved IPs

默认日志写到：

```bash
/Users/lex/git/knowledge/macos/output/app-network-YYYY-MM-DD_HH-MM-SS.jsonl
```

## 重要限制

这个脚本是非侵入式观察工具，不会修改系统 DNS。它的域名关联是 best effort：

- APP 如果使用 DNS 缓存，启动时可能不会产生新的 DNS 查询
- APP 如果使用 DoH/DoT，tcpdump 看不到传统 53 端口 DNS
- APP 如果走代理、VPN、Private Relay，看到的可能是代理目标
- 有些域名解析由 helper 进程完成，不一定能 100% 归属到主 APP
- `lsof` 能准确给出进程连接的远程 IP/端口，但不能天然给出原始域名

如果要做更强的系统级归因，下一步通常是 Network Extension、商业防火墙类工具，或者抓包加 TLS SNI/HTTP Host 解析。
