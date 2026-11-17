#!/bin/bash

# Secret Manager 迁移 - 应用配置更新脚本
# 功能：更新应用程序配置以使用新项目的密钥

set -euo pipefail

# 加载配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# 更新 Kubernetes 部署中的项目引用
update_k8s_deployments() {
    local namespace=$1
    
    log_info "更新 Kubernetes 命名空间 $namespace 中的 Secret Manager 项目引用..."
    
    # 检查命名空间是否存在
    if ! kubectl get namespace "$namespace" &>/dev/null; then
        log_warning "命名空间 $namespace 不存在，跳过"
        return 0
    fi
    
    # 获取所有部署
    local deployments
    deployments=$(kubectl get deployments -n "$namespace" -o name 2>/dev/null || echo "")
    
    if [[ -z "$deployments" ]]; then
        log_info "命名空间 $namespace 中没有部署"
        return 0
    fi
    
    local updated_count=0
    local skipped_count=0
    
    while IFS= read -r deployment; do
        if [[ -n "$deployment" ]]; then
            log_debug "检查部署: $deployment"
            
            # 获取部署配置
            local deployment_yaml
            deployment_yaml=$(kubectl get "$deployment" -n "$namespace" -o yaml)
            
            # 检查是否包含源项目引用
            if echo "$deployment_yaml" | grep -q "projects/$SOURCE_PROJECT/secrets"; then
                log_info "发现项目引用，准备更新: $deployment"
                
                # 创建备份
                local backup_file="$BACKUP_DIR/k8s_backups/$(echo "${namespace}_${deployment}" | tr '/' '_').yaml"
                mkdir -p "$(dirname "$backup_file")"
                echo "$deployment_yaml" > "$backup_file"
                
                # 更新项目引用
                local updated_yaml
                updated_yaml=$(echo "$deployment_yaml" | sed "s|projects/$SOURCE_PROJECT/secrets|projects/$TARGET_PROJECT/secrets|g")
                
                # 应用更新
                if echo "$updated_yaml" | kubectl apply -f -; then
                    log_success "部署更新成功: $deployment"
                    ((updated_count++))
                else
                    log_error "部署更新失败: $deployment"
                    log_info "可以从备份恢复: kubectl apply -f $backup_file"
                fi
            else
                log_debug "部署无需更新: $deployment"
                ((skipped_count++))
            fi
        fi
    done <<< "$deployments"
    
    log_info "命名空间 $namespace 更新完成 - 更新: $updated_count, 跳过: $skipped_count"
}

# 更新 ConfigMaps 中的项目引用
update_k8s_configmaps() {
    local namespace=$1
    
    log_info "更新 Kubernetes 命名空间 $namespace 中的 ConfigMaps..."
    
    # 获取所有 ConfigMaps
    local configmaps
    configmaps=$(kubectl get configmaps -n "$namespace" -o name 2>/dev/null || echo "")
    
    if [[ -z "$configmaps" ]]; then
        log_info "命名空间 $namespace 中没有 ConfigMaps"
        return 0
    fi
    
    local updated_count=0
    local skipped_count=0
    
    while IFS= read -r configmap; do
        if [[ -n "$configmap" ]]; then
            log_debug "检查 ConfigMap: $configmap"
            
            # 获取 ConfigMap 配置
            local configmap_yaml
            configmap_yaml=$(kubectl get "$configmap" -n "$namespace" -o yaml)
            
            # 检查是否包含源项目引用
            if echo "$configmap_yaml" | grep -q "$SOURCE_PROJECT"; then
                log_info "发现项目引用，准备更新: $configmap"
                
                # 创建备份
                local backup_file="$BACKUP_DIR/k8s_backups/$(echo "${namespace}_${configmap}" | tr '/' '_').yaml"
                mkdir -p "$(dirname "$backup_file")"
                echo "$configmap_yaml" > "$backup_file"
                
                # 更新项目引用
                local updated_yaml
                updated_yaml=$(echo "$configmap_yaml" | sed "s|$SOURCE_PROJECT|$TARGET_PROJECT|g")
                
                # 应用更新
                if echo "$updated_yaml" | kubectl apply -f -; then
                    log_success "ConfigMap 更新成功: $configmap"
                    ((updated_count++))
                else
                    log_error "ConfigMap 更新失败: $configmap"
                    log_info "可以从备份恢复: kubectl apply -f $backup_file"
                fi
            else
                log_debug "ConfigMap 无需更新: $configmap"
                ((skipped_count++))
            fi
        fi
    done <<< "$configmaps"
    
    log_info "ConfigMaps 更新完成 - 更新: $updated_count, 跳过: $skipped_count"
}

# 扫描并更新配置文件
scan_and_update_config_files() {
    local search_dir=${1:-.}
    
    log_info "扫描目录 $search_dir 中的配置文件..."
    
    local updated_files=()
    local total_files=0
    
    # 扫描配置文件
    for pattern in "${CONFIG_FILE_PATTERNS[@]}"; do
        while IFS= read -r -d '' file; do
            ((total_files++))
            
            if [[ -f "$file" ]]; then
                log_debug "检查文件: $file"
                
                # 检查文件是否包含源项目引用
                if grep -q "$SOURCE_PROJECT" "$file" 2>/dev/null; then
                    log_info "发现项目引用，准备更新: $file"
                    
                    # 创建备份
                    local backup_file="$BACKUP_DIR/config_backups/$(echo "$file" | tr '/' '_').bak"
                    mkdir -p "$(dirname "$backup_file")"
                    cp "$file" "$backup_file"
                    
                    # 更新文件内容
                    if sed -i.tmp "s|$SOURCE_PROJECT|$TARGET_PROJECT|g" "$file" && rm -f "${file}.tmp"; then
                        log_success "文件更新成功: $file"
                        updated_files+=("$file")
                    else
                        log_error "文件更新失败: $file"
                        log_info "可以从备份恢复: cp $backup_file $file"
                    fi
                fi
            fi
        done < <(find "$search_dir" -name "$pattern" -type f -print0 2>/dev/null)
    done
    
    log_info "配置文件扫描完成 - 总计: $total_files, 更新: ${#updated_files[@]}"
    
    # 生成更新文件列表
    if [[ ${#updated_files[@]} -gt 0 ]]; then
        local updated_files_list="$BACKUP_DIR/updated_config_files.txt"
        printf '%s\n' "${updated_files[@]}" > "$updated_files_list"
        log_success "更新文件列表: $updated_files_list"
    fi
}

# 生成环境变量更新指南
generate_env_update_guide() {
    local guide_file="$BACKUP_DIR/environment_variables_update_guide.txt"
    
    log_info "生成环境变量更新指南..."
    
    cat > "$guide_file" << EOF
# 环境变量更新指南
更新时间: $(date)
源项目: $SOURCE_PROJECT
目标项目: $TARGET_PROJECT

## 需要更新的环境变量模式

### 1. 直接项目引用
旧值: projects/$SOURCE_PROJECT/secrets/secret-name/versions/latest
新值: projects/$TARGET_PROJECT/secrets/secret-name/versions/latest

### 2. 项目ID环境变量
旧值: GCP_PROJECT=$SOURCE_PROJECT
新值: GCP_PROJECT=$TARGET_PROJECT

旧值: GOOGLE_CLOUD_PROJECT=$SOURCE_PROJECT
新值: GOOGLE_CLOUD_PROJECT=$TARGET_PROJECT

### 3. Secret Manager 客户端配置
确保应用程序使用正确的项目ID初始化 Secret Manager 客户端

## 常见配置文件位置
- Kubernetes Deployments 和 ConfigMaps
- Docker Compose 文件 (docker-compose.yml)
- 应用程序配置文件 (.env, config.json, application.yml)
- CI/CD 管道配置 (.github/workflows/, .gitlab-ci.yml)
- Terraform 变量文件 (*.tf, *.tfvars)
- Helm Charts (values.yaml, templates/)

## 验证命令

### Kubernetes 环境
# 检查 Deployments
kubectl get deployments -A -o yaml | grep -i "$SOURCE_PROJECT"

# 检查 ConfigMaps
kubectl get configmaps -A -o yaml | grep -i "$SOURCE_PROJECT"

# 检查 Secrets
kubectl get secrets -A -o yaml | grep -i "$SOURCE_PROJECT"

### 本地环境
# 检查环境变量
env | grep -i "$SOURCE_PROJECT"

# 检查配置文件
grep -r "$SOURCE_PROJECT" . --include="*.yaml" --include="*.yml" --include="*.json" --include="*.env"

## 应用程序代码更新

### Python 示例
\`\`\`python
# 旧代码
from google.cloud import secretmanager
client = secretmanager.SecretManagerServiceClient()
name = f"projects/$SOURCE_PROJECT/secrets/my-secret/versions/latest"

# 新代码
from google.cloud import secretmanager
client = secretmanager.SecretManagerServiceClient()
name = f"projects/$TARGET_PROJECT/secrets/my-secret/versions/latest"
\`\`\`

### Node.js 示例
\`\`\`javascript
// 旧代码
const {SecretManagerServiceClient} = require('@google-cloud/secret-manager');
const client = new SecretManagerServiceClient();
const name = \`projects/$SOURCE_PROJECT/secrets/my-secret/versions/latest\`;

// 新代码
const {SecretManagerServiceClient} = require('@google-cloud/secret-manager');
const client = new SecretManagerServiceClient();
const name = \`projects/$TARGET_PROJECT/secrets/my-secret/versions/latest\`;
\`\`\`

### Go 示例
\`\`\`go
// 旧代码
name := "projects/$SOURCE_PROJECT/secrets/my-secret/versions/latest"

// 新代码
name := "projects/$TARGET_PROJECT/secrets/my-secret/versions/latest"
\`\`\`

## 测试验证

### 1. 功能测试
- 验证应用程序能够正常启动
- 测试所有依赖密钥的功能
- 检查日志中是否有错误信息

### 2. 连接测试
\`\`\`bash
# 测试密钥访问
gcloud secrets versions access latest --secret="my-secret" --project=$TARGET_PROJECT
\`\`\`

### 3. 监控检查
- 检查应用程序监控指标
- 验证错误率没有增加
- 确认性能指标正常

## 回滚计划

如果更新后出现问题，可以快速回滚：

### Kubernetes 回滚
\`\`\`bash
# 恢复 Deployment
kubectl apply -f $BACKUP_DIR/k8s_backups/

# 或使用 kubectl rollout
kubectl rollout undo deployment/my-app -n my-namespace
\`\`\`

### 配置文件回滚
\`\`\`bash
# 恢复配置文件
cp $BACKUP_DIR/config_backups/* /path/to/original/location/
\`\`\`

## 注意事项

1. **分批更新**: 建议分批更新应用程序，先更新非关键服务
2. **监控观察**: 更新后密切监控应用程序状态
3. **备份保留**: 保留所有备份文件直到确认迁移成功
4. **团队通知**: 及时通知相关团队配置更改
5. **文档更新**: 更新相关文档和运维手册

## 常见问题

### Q: 应用程序报告"权限被拒绝"错误
A: 检查目标项目中的 IAM 权限配置，确保服务账户有访问密钥的权限

### Q: 某些密钥无法访问
A: 验证密钥是否已成功迁移，检查密钥名称是否正确

### Q: 性能下降
A: 检查网络配置，确保应用程序能够高效访问新项目的 Secret Manager

EOF
    
    log_success "环境变量更新指南生成完成: $guide_file"
    echo "$guide_file"
}

# 生成应用切换检查清单
generate_app_switch_checklist() {
    local checklist_file="$BACKUP_DIR/app_switch_checklist.md"
    
    log_info "生成应用切换检查清单..."
    
    cat > "$checklist_file" << EOF
# 应用切换检查清单

## 迁移前检查
- [ ] 所有密钥已成功迁移到目标项目
- [ ] 密钥验证通过 (运行 ./05-verify.sh)
- [ ] 应用程序配置已更新
- [ ] 备份文件已创建
- [ ] 团队成员已通知

## 切换准备
- [ ] 选择合适的维护窗口
- [ ] 准备回滚计划
- [ ] 设置监控和告警
- [ ] 准备应急联系方式

## 切换步骤

### 1. Kubernetes 应用更新
- [ ] 更新 Deployments 中的项目引用
- [ ] 更新 ConfigMaps 中的配置
- [ ] 更新 Secrets 中的引用
- [ ] 验证 Pod 重启正常

### 2. 环境变量更新
- [ ] 更新系统环境变量
- [ ] 更新应用程序配置文件
- [ ] 更新 CI/CD 管道配置
- [ ] 更新 Docker 镜像配置

### 3. 应用程序代码更新
- [ ] 更新硬编码的项目ID
- [ ] 更新 Secret Manager 客户端配置
- [ ] 重新构建和部署应用程序
- [ ] 验证代码更改

### 4. 基础设施更新
- [ ] 更新 Terraform 配置
- [ ] 更新 Helm Charts
- [ ] 更新 Ansible Playbooks
- [ ] 更新其他 IaC 工具配置

## 切换后验证

### 应用程序验证
- [ ] 应用程序正常启动
- [ ] 所有服务健康检查通过
- [ ] 可以正常访问密钥
- [ ] 所有功能正常工作
- [ ] 日志无错误信息

### 性能验证
- [ ] 响应时间正常
- [ ] 吞吐量无明显下降
- [ ] 错误率在正常范围内
- [ ] 资源使用率正常

### 安全验证
- [ ] IAM 权限配置正确
- [ ] 密钥访问权限正常
- [ ] 审计日志记录正常
- [ ] 安全扫描无异常

## 监控检查
- [ ] 应用程序监控正常
- [ ] 基础设施监控正常
- [ ] 告警规则工作正常
- [ ] 日志收集正常

## 回滚计划

如果出现问题，按以下顺序执行回滚：

### 紧急回滚 (5分钟内)
1. **Kubernetes 回滚**
   \`\`\`bash
   kubectl apply -f $BACKUP_DIR/k8s_backups/
   \`\`\`

2. **配置文件回滚**
   \`\`\`bash
   # 恢复配置文件
   find $BACKUP_DIR/config_backups/ -name "*.bak" -exec bash -c 'cp "\$1" "\${1%.bak}"' _ {} \\;
   \`\`\`

3. **重启应用程序**
   \`\`\`bash
   kubectl rollout restart deployment/my-app -n my-namespace
   \`\`\`

### 完整回滚 (15分钟内)
1. 执行紧急回滚步骤
2. 恢复环境变量配置
3. 重新部署应用程序
4. 验证功能恢复

## 清理步骤（迁移成功后）

### 立即清理
- [ ] 验证所有应用程序正常运行 24 小时
- [ ] 确认无用户投诉或问题报告
- [ ] 检查监控指标稳定

### 1周后清理
- [ ] 删除源项目中的密钥（可选）
- [ ] 清理备份文件
- [ ] 更新文档和运维手册
- [ ] 归档迁移记录

### 1个月后清理
- [ ] 删除迁移相关的临时资源
- [ ] 清理旧的监控配置
- [ ] 更新灾难恢复计划

## 联系信息

### 技术团队
- 迁移负责人: _______________
- 应用开发团队: _______________
- 运维团队: _______________
- 安全团队: _______________

### 紧急联系
- 技术支持: _______________
- 值班电话: _______________
- 管理层联系: _______________

## 成功标准

### 技术指标
- [ ] 应用程序可用性 > 99.9%
- [ ] 响应时间无明显增加 (< 10% 增长)
- [ ] 错误率 < 0.1%
- [ ] 所有功能测试通过

### 业务指标
- [ ] 用户投诉数量无增加
- [ ] 业务功能正常
- [ ] 数据完整性保持
- [ ] 合规要求满足

## 经验教训记录

### 成功经验
- 记录迁移过程中的成功做法
- 总结有效的工具和方法
- 记录团队协作亮点

### 改进建议
- 记录遇到的问题和解决方案
- 提出流程改进建议
- 更新迁移最佳实践

---

**注意**: 此检查清单应根据具体应用程序和环境进行调整。建议在测试环境先完整执行一遍。
EOF
    
    log_success "应用切换检查清单生成完成: $checklist_file"
    echo "$checklist_file"
}

# 生成更新报告
generate_update_report() {
    local report_file="$BACKUP_DIR/app_update_report.txt"
    
    log_info "生成应用更新报告..."
    
    cat > "$report_file" << EOF
# 应用配置更新报告
更新时间: $(date)
源项目: $SOURCE_PROJECT
目标项目: $TARGET_PROJECT

## 更新摘要
EOF
    
    # 统计 Kubernetes 更新
    local k8s_backups
    k8s_backups=$(find "$BACKUP_DIR/k8s_backups" -name "*.yaml" 2>/dev/null | wc -l || echo "0")
    echo "Kubernetes 资源更新: $k8s_backups 个文件" >> "$report_file"
    
    # 统计配置文件更新
    local config_backups
    config_backups=$(find "$BACKUP_DIR/config_backups" -name "*.bak" 2>/dev/null | wc -l || echo "0")
    echo "配置文件更新: $config_backups 个文件" >> "$report_file"
    
    cat >> "$report_file" << EOF

## 备份位置
Kubernetes 备份: $BACKUP_DIR/k8s_backups/
配置文件备份: $BACKUP_DIR/config_backups/

## 生成的指南
环境变量更新指南: $BACKUP_DIR/environment_variables_update_guide.txt
应用切换检查清单: $BACKUP_DIR/app_switch_checklist.md

## 验证建议
1. 检查所有更新的资源是否正常运行
2. 验证应用程序能够访问新项目的密钥
3. 监控应用程序日志和性能指标
4. 进行功能测试确保所有特性正常

## 回滚信息
如需回滚，请使用备份目录中的文件：
- Kubernetes: kubectl apply -f $BACKUP_DIR/k8s_backups/
- 配置文件: 从 $BACKUP_DIR/config_backups/ 恢复

## 后续步骤
1. 验证应用程序功能
2. 监控系统稳定性
3. 完成应用切换检查清单
4. 考虑清理源项目资源
EOF
    
    log_success "应用更新报告生成完成: $report_file"
    echo "$report_file"
}

# 更新迁移状态
update_migration_status() {
    local status_file="$BACKUP_DIR/migration_status.json"
    
    if [[ -f "$status_file" ]]; then
        jq '.stages.update = "completed" | .last_updated = now | .update_completed_at = now' "$status_file" > "${status_file}.tmp"
        mv "${status_file}.tmp" "$status_file"
        log_debug "迁移状态已更新"
    fi
}

# 主函数
main() {
    log_info "=== Secret Manager 应用配置更新开始 ==="
    
    # 检查环境
    if [[ ! -f "$BACKUP_DIR/migration_status.json" ]]; then
        log_error "未找到迁移状态文件，请先运行 ./01-setup.sh"
        exit 1
    fi
    
    # 检查验证阶段是否完成
    local verify_status
    verify_status=$(jq -r '.stages.verify' "$BACKUP_DIR/migration_status.json" 2>/dev/null || echo "pending")
    
    if [[ "$verify_status" != "completed" ]]; then
        log_warning "密钥验证阶段未完成，建议先运行 ./05-verify.sh"
        read -p "是否继续应用配置更新？(y/n): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "用户取消操作"
            exit 0
        fi
    fi
    
    # 1. 更新 Kubernetes 资源
    log_info "步骤 1: 更新 Kubernetes 资源"
    
    # 检查是否有 kubectl 访问权限
    if kubectl version --client &>/dev/null; then
        read -p "是否更新 Kubernetes 部署中的项目引用？(y/n): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            for namespace in "${K8S_NAMESPACES[@]}"; do
                log_info "处理命名空间: $namespace"
                update_k8s_deployments "$namespace"
                update_k8s_configmaps "$namespace"
            done
        fi
    else
        log_warning "kubectl 不可用，跳过 Kubernetes 资源更新"
    fi
    
    # 2. 扫描和更新配置文件
    log_info "步骤 2: 扫描和更新配置文件"
    read -p "是否扫描当前目录的配置文件？(y/n): " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        read -p "请输入扫描目录 (默认: 当前目录): " -r scan_dir
        scan_dir=${scan_dir:-.}
        scan_and_update_config_files "$scan_dir"
    fi
    
    # 3. 生成更新指南
    log_info "步骤 3: 生成更新指南和检查清单"
    local env_guide
    env_guide=$(generate_env_update_guide)
    
    local checklist
    checklist=$(generate_app_switch_checklist)
    
    # 4. 生成更新报告
    log_info "步骤 4: 生成更新报告"
    local report_file
    report_file=$(generate_update_report)
    
    # 5. 更新状态
    update_migration_status
    
    log_success "=== Secret Manager 应用配置更新完成 ==="
    
    echo ""
    echo "更新结果摘要："
    echo "📋 环境变量指南: $env_guide"
    echo "✅ 切换检查清单: $checklist"
    echo "📄 更新报告: $report_file"
    echo "💾 备份目录: $BACKUP_DIR"
    echo ""
    echo "重要提醒："
    echo "1. 仔细阅读环境变量更新指南"
    echo "2. 按照检查清单逐步验证"
    echo "3. 在生产环境切换前进行充分测试"
    echo "4. 保留备份文件直到确认迁移成功"
    echo ""
    echo "下一步："
    echo "1. 查看更新指南: cat $env_guide"
    echo "2. 执行切换检查清单: cat $checklist"
    echo "3. 测试应用程序功能"
    echo "4. 监控生产环境稳定性"
}

# 执行主函数
main "$@"