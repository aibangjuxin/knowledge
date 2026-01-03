# 5 分钟快速开始

## 🎯 目标

让你的 Node.js 应用在 5 分钟内适配平台的 ConfigMap 配置。

## ✅ 前置条件

- Node.js 18+
- 已有 Node.js 应用（使用 Express/Koa/Fastify 或原生 http）

## 🚀 三步集成

### 第 1 步：复制配置加载器（30 秒）

```bash
# 在你的项目根目录
mkdir -p lib/config
cp platform-config-loader.js lib/config/
```

### 第 2 步：修改 server.js（2 分钟）

```javascript
const express = require('express');
const https = require('https');
const fs = require('fs');
const { loadPlatformConfig } = require('./lib/config/platform-config-loader');

async function main() {
    // 加载平台配置
    const config = await loadPlatformConfig();
    
    const app = express();
    
    // 使用 Context Path（关键！）
    const router = express.Router();
    router.get('/health', (req, res) => {
        res.json({ status: 'ok' });
    });
    // 你的其他路由...
    
    app.use(config.contextPath, router);
    
    // 启动服务
    if (config.sslEnabled) {
        const options = {
            key: fs.readFileSync(config.keyPath),
            cert: fs.readFileSync(config.certPath)
        };
        https.createServer(options, app).listen(config.port);
    } else {
        app.listen(config.port);
    }
}

main();
```

### 第 3 步：测试（2 分钟）

```bash
# 本地测试
chmod +x test-local.sh
./test-local.sh

# 在另一个终端
curl -k https://localhost:8443/user-service/v1/health
```

## ✨ 完成！

你的应用现在已经：
- ✅ 读取平台 ConfigMap 配置
- ✅ 支持统一的 Context Path
- ✅ 支持 HTTPS
- ✅ 与 Java 应用使用相同配置

## 📦 部署到 K8S

```bash
# 构建镜像
docker build -t your-registry/your-app:latest .

# 部署（选择一个）
kubectl apply -f deployment-nodejs-separate-cm.yaml  # 如果平台提供 PEM 证书
```

## 🔍 验证部署

```bash
# 查看 Pod
kubectl get pods

# 查看日志
kubectl logs <pod-name>

# 测试健康检查
kubectl exec -it <pod-name> -- curl -k https://localhost:8443/user-service/v1/health
```

## 📚 下一步

- 详细集成指南：[INTEGRATION-GUIDE.md](INTEGRATION-GUIDE.md)
- 完整技术方案：[platform-configmap-adapter.md](platform-configmap-adapter.md)
- Java 对比：[JAVA-NODEJS-COMPARISON.md](JAVA-NODEJS-COMPARISON.md)

## ❓ 遇到问题？

| 问题 | 解决方案 |
|------|----------|
| 配置文件读取失败 | 检查 ConfigMap 是否挂载到 `/opt/config` |
| 证书文件不存在 | 使用证书转换脚本或 InitContainer |
| 健康检查失败 | 确认路径包含 Context Path |
| 404 错误 | 确认所有路由都在 `app.use(contextPath, router)` 下 |

查看完整故障排查：[INTEGRATION-GUIDE.md#故障排查](INTEGRATION-GUIDE.md)

---

**用时**：5 分钟  
**难度**：⭐⭐ (简单)  
**维护**：平台工程团队
