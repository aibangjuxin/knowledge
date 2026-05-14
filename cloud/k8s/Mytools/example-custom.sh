#!/bin/bash

# 示例自定义配置文件
# 将此文件复制到宿主机挂载目录 /opt/share/custom.sh
# 容器启动时会自动加载此配置

echo "🎯 加载个人自定义配置..."

# ============================================================================
# 个人环境变量
# ============================================================================

# 设置个人工作目录
export MY_WORKSPACE="/opt/share/workspace"
export MY_PROJECTS="/opt/share/projects"

# 设置常用服务器地址
export TARGET_SERVER="192.168.1.100"
export TEST_DOMAIN="example.com"

# ============================================================================
# 个人别名
# ============================================================================

# 快速连接常用服务器
alias ssh-target='ssh root@$TARGET_SERVER'
alias ssh-test='ssh user@test.example.com'

# 个人常用扫描命令
alias scan-target='nmap -A -T4 $TARGET_SERVER'
alias scan-domain='nmap -A -T4 $TEST_DOMAIN'

# 快速启动常用工具
alias start-burp='java -jar ~/tools/burpsuite.jar &'
alias start-zap='zap.sh &'

# ============================================================================
# 个人函数
# ============================================================================

# 个人项目管理函数
create-project() {
    if [ $# -eq 0 ]; then
        echo "用法: create-project <项目名>"
        return 1
    fi
    
    local project_name=$1
    local project_dir="$MY_PROJECTS/$project_name"
    
    mkdir -p "$project_dir"/{scans,reports,screenshots,notes,tools}
    
    # 创建项目说明文件
    cat > "$project_dir/README.md" << EOF
# $project_name

## 项目信息
- 创建时间: $(date)
- 目标: 
- 范围: 

## 目录结构
- scans/     - 扫描结果
- reports/   - 测试报告
- screenshots/ - 截图
- notes/     - 笔记
- tools/     - 项目专用工具

## 进度记录
- [ ] 信息收集
- [ ] 漏洞扫描
- [ ] 手工测试
- [ ] 报告编写
EOF
    
    echo "✅ 项目创建完成: $project_dir"
    cd "$project_dir"
}

# 快速备份函数
backup-config() {
    local backup_dir="/opt/share/backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    # 备份重要配置
    cp ~/.zshrc "$backup_dir/"
    cp -r ~/.ssh "$backup_dir/" 2>/dev/null || true
    cp -r ~/.kube "$backup_dir/" 2>/dev/null || true
    
    echo "✅ 配置备份完成: $backup_dir"
}

# 环境重置函数
reset-env() {
    echo "🔄 重置环境配置..."
    
    # 清理临时文件
    rm -rf /tmp/*
    
    # 重新加载配置
    source ~/.zshrc
    
    echo "✅ 环境重置完成"
}

# ============================================================================
# 启动时执行的命令
# ============================================================================

# 检查挂载目录
if [ ! -d "$MY_WORKSPACE" ]; then
    mkdir -p "$MY_WORKSPACE"
fi

if [ ! -d "$MY_PROJECTS" ]; then
    mkdir -p "$MY_PROJECTS"
fi

# 显示个人配置信息
echo "📋 个人配置已加载:"
echo "  工作目录: $MY_WORKSPACE"
echo "  项目目录: $MY_PROJECTS"
echo "  目标服务器: $TARGET_SERVER"
echo "  测试域名: $TEST_DOMAIN"

echo "✅ 个人自定义配置加载完成"