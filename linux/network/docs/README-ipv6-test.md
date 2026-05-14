# IPv6 Network Test Script for macOS

## 概述

这个脚本基于 test-ipv6.com 的测试逻辑，专门为macOS系统设计，用于测试本地网络的IPv6支持情况。

## 功能特点

- ✅ 检查系统IPv6支持
- ✅ 测试IPv4/IPv6 DNS记录解析
- ✅ 测试双栈网络连接
- ✅ 大包传输测试
- ✅ ISP DNS IPv6支持检测
- ✅ 服务提供商ASN信息查询
- ✅ macOS网络配置检查

## 使用方法

```bash
# 运行测试
./test-ipv6-local.sh

# 或者直接用bash运行
/opt/homebrew/bin/bash test-ipv6-local.sh
```

## 依赖要求

脚本会自动检查以下依赖：
- `curl` - 网络连接测试
- `dig` - DNS查询 (可通过 `brew install bind` 安装)
- `bc` - 数学计算
- `ping`/`ping6` - 网络连通性测试

## 测试项目

1. **IPv6系统支持** - 检查macOS是否启用IPv6
2. **IPv6地址分配** - 查看是否获得全局IPv6地址
3. **IPv4 DNS记录测试** - 测试IPv4连接
4. **IPv6 DNS记录测试** - 测试IPv6连接
5. **双栈DNS记录测试** - 测试双栈网络偏好
6. **双栈大包测试** - 测试MTU和大包传输
7. **IPv6大包测试** - 专门的IPv6大包测试
8. **DNS服务器IPv6支持** - 检查DNS服务器配置
9. **ISP DNS IPv6测试** - 测试ISP的IPv6 DNS支持
10. **IPv4服务提供商查询** - 获取IPv4 ASN信息
11. **IPv6服务提供商查询** - 获取IPv6 ASN信息
12. **macOS网络配置** - 检查系统网络设置

## 输出示例

```
=== IPv6 Network Connectivity Test ===
Testing IPv6 support for your local network...

1. Testing IPv6 system support...
✓ IPv6 system support (0.001s)

2. Checking IPv6 address assignment...
✓ IPv6 address found: 2001:db8::1 (0.001s)

3. Testing with IPv4 DNS record...
✓ Test with IPv4 DNS record using ipv4 (2.246s)

...

=== Test Summary ===
Total tests: 12
Passed: 10
Failed: 2
IPv6 Readiness: Excellent (83%)
Your network has good IPv6 support!
```

## 故障排除

### 常见问题

1. **dig命令未找到**
   ```bash
   brew install bind
   ```

2. **ping6命令不可用**
   - macOS较新版本使用 `ping -6` 替代 `ping6`
   - 脚本会自动处理这种情况

3. **IPv6地址未分配**
   - 检查路由器IPv6设置
   - 联系ISP确认IPv6支持

4. **DNS解析失败**
   - 检查网络连接
   - 尝试更换DNS服务器

## 网络配置建议

### 如果IPv6支持较差：
- 联系ISP询问IPv6支持
- 检查路由器IPv6配置
- 验证防火墙IPv6规则

### 如果IPv6支持良好：
- 考虑在应用中启用IPv6
- 测试更多IPv6服务
- 监控IPv6连接质量

## 技术说明

脚本针对macOS进行了以下优化：
- 使用 `ifconfig` 替代 `ip` 命令
- 使用 `sysctl` 检查IPv6状态
- 使用 `networksetup` 检查网络配置
- 使用 `scutil` 获取DNS配置
- 兼容 `ping` 和 `ping6` 命令

## 许可证

MIT License - 可自由使用和修改