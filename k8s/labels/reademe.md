创建了三个脚本来解决你的需求：

1. add-deployment-labels.sh - 基础版本
直接在脚本里配置你的 deployment 列表和 label，适合固定的场景：

# 修改脚本中的配置
NAMESPACE="your-namespace"
LABEL_KEY="lex"
LABEL_VALUE="enabled"
DEPLOYMENTS=("app1" "app2" "app3")

# 运行脚本
./add-deployment-labels.sh
2. add-deployment-labels-flexible.sh - 灵活版本
通过命令行参数传递配置，更灵活：

# 使用示例
./add-deployment-labels-flexible.sh -n my-namespace -l lex=enabled -d "app1,app2,app3"
3. deployment-helper.sh - 辅助工具
用于查看状态和手动重启：

# 列出所有 deployment
./deployment-helper.sh list -n my-namespace

# 检查带特定 label 的 pods
./deployment-helper.sh check -n my-namespace -l lex=enabled

# 手动重启某个 deployment
./deployment-helper.sh restart -n my-namespace -d my-app
脚本功能特点：
✅ 自动添加 label 到 pod template - 确保新 pod 带有 label
✅ 触发滚动更新 - 重新创建 pod 使 label 生效
✅ 等待更新完成 - 确保操作成功
✅ 验证结果 - 检查 pod 是否正确带有 label
✅ 错误处理 - 检查 namespace 和 deployment 是否存在
✅ 进度显示 - 清晰的执行状态反馈

现在你只需要：

修改脚本中的 namespace、label 和 deployment 列表
运行脚本
等待 pod 重启完成
你的 pod 就能访问目标 namespace 的服务了