# K8s集群迁移POC方案

## 项目概述

这是一个K8s集群迁移的POC方案，通过反向代理的方式实现从旧集群到新集群的平滑迁移。

### 核心思路
```
用户请求 -> 旧域名 -> 旧集群Ingress -> 反向代理 -> 新集群服务
```

## 文件结构

```
ali/migrate-plan/
├── README.md                 # 本文件，项目总览
├── backgroud.md             # 需求背景和现状分析  
├── migrate-claude.md        # 详细的技术方案和脚本
├── poc-analysis.md          # POC可行性分析
├── poc-implementation.md    # POC具体实施指南
└── poc-test.sh             # POC验证脚本
```

## 快速开始

### 1. 环境要求
- kubectl已配置并连接到旧集群
- 新集群服务已部署并可通过新域名访问
- 具有旧集群的管理权限

### 2. 执行POC验证
```bash
# 进入项目目录
cd ali/migrate-plan

# 执行完整POC验证
./poc-test.sh full
```

### 3. 验证结果
脚本会自动：
- 备份原始配置
- 创建代理服务
- 更新Ingress配置
- 验证代理功能
- 执行性能测试

### 4. 回滚（如需要）
```bash
./poc-test.sh rollback
```

## 方案优势

1. **零停机迁移**: 用户无感知切换
2. **风险可控**: 可快速回滚
3. **配置简单**: 利用现有nginx-ingress功能
4. **成本低**: 无需额外基础设施

## 技术细节

### 关键配置
- `nginx.ingress.kubernetes.io/upstream-vhost`: 指定真实的upstream主机
- `nginx.ingress.kubernetes.io/proxy-set-headers`: 设置正确的请求头
- `ExternalName Service`: 将请求路由到外部域名

### 验证要点
- HTTP/HTTPS正常工作
- 请求头正确传递  
- 性能影响在可接受范围
- 错误处理正常

## 下一步计划

POC验证成功后：

1. **开发批量迁移脚本** - 支持多个服务同时迁移
2. **制定灰度策略** - 分批次迁移降低风险
3. **完善监控告警** - 确保迁移过程可观测
4. **准备生产部署** - 制定详细的迁移计划

## 注意事项

1. **SSL证书**: 确保新集群有对应的SSL证书
2. **会话保持**: 如果应用有session sticky需求需要额外配置
3. **健康检查**: 配置upstream健康检查
4. **性能监控**: 关注代理层的性能影响

## 支持

如有问题，请参考：
- `poc-analysis.md` - 详细的技术分析
- `poc-implementation.md` - 实施步骤指南
- `migrate-claude.md` - 完整的解决方案

## 版本历史

- v1.0 - 初始POC方案
- 计划v2.0 - 批量迁移脚本
- 计划v3.0 - 生产级监控和告警