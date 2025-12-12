➜  scripts git:(main) ./pod_measure_startup_fixed.sh -n lex nginx-deployment-854b5bc678-m428j
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
测量 Pod 启动时间: nginx-deployment-854b5bc678-m428j (命名空间: lex)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📋 步骤 1: 获取 Pod 基本信息
   Pod 创建时间: 2025-10-29T10:58:34Z
   容器启动时间: 2025-11-30T05:07:28Z

📋 步骤 2: 分析就绪探针配置
   就绪探针配置:
{
  "failureThreshold": 3,
  "httpGet": {
    "path": "/",
    "port": 80,
    "scheme": "HTTP"
  },
  "periodSeconds": 20,
  "successThreshold": 1,
  "timeoutSeconds": 3
}

   提取的探针参数:
   - Scheme: HTTP
   - Port: 80
   - Path: /
   - Initial Delay: 0s
   - Period: 20s
   - Failure Threshold: 3

⏱️  步骤 3: 检查 Pod Ready 状态
   Pod 已处于 Ready 状态
   Ready 时间: 2025-11-30T05:07:38Z

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 最终结果 (Result)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ 应用程序启动耗时: 10 秒
   (基于 Kubernetes Ready 状态)

📋 当前探针配置分析:
   - 当前配置允许的最大启动时间: 60 秒
   - 实际启动时间: 10 秒
   ✓ 当前配置足够

💡 建议的优化配置:
   readinessProbe:
     httpGet:
       path: /
       port: 80
       scheme: HTTP
     initialDelaySeconds: 0
     periodSeconds: 20
     failureThreshold: 1

📋 或者使用 startupProbe (推荐):
   startupProbe:
     httpGet:
       path: /
       port: 80
       scheme: HTTP
     initialDelaySeconds: 0
     periodSeconds: 10
     failureThreshold: 1
   readinessProbe:
     httpGet:
       path: /
       port: 80
       scheme: HTTP
     initialDelaySeconds: 0
     periodSeconds: 5
     failureThreshold: 3
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━