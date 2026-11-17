list-all-secrets-simple-optimized.sh
这个是OK的
创建了一个更简单的版本 list-all-secrets-simple-optimized.sh，它：

避免了所有复杂的 bash 语法 - 使用简单的 heredoc 和直接追加
直接拼接 JSON - 在循环中直接写入，用逗号分隔
最小化临时文件 - 只保留必要的 IAM 策略文件
单行 jq 命令 - 避免多行字符串的语法问题
现在你可以使用这个简化版本：

bash list-all-secrets-simple-optimized.sh my-project
这个版本：

✅ 避免了所有 bash 语法错误
✅ 支持大小写混合的 Secret 名称
✅ 使用并行处理（20 个任务）
✅ 直接拼接 JSON，不需要最后合并
✅ 生成 CSV、JSON 和汇总报告
✅ 代码简单清晰