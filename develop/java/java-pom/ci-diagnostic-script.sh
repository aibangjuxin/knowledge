#!/bin/bash

################################################################################
# CI 环境依赖问题诊断脚本
# 用途：在 CI Pipeline 中运行，自动诊断 Maven 依赖问题
# 使用：bash ci-diagnostic-script.sh [dependency-name]
################################################################################

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 依赖名称（可选参数）
DEPENDENCY_NAME=${1:-"wiremock"}

echo "========================================="
echo "CI 环境依赖问题诊断工具"
echo "========================================="
echo "诊断目标: ${DEPENDENCY_NAME}"
echo "时间: $(date)"
echo "========================================="

# 计数器
ISSUES_FOUND=0

################################################################################
# 1. Maven 环境信息
################################################################################
echo -e "\n${BLUE}[1/10] Maven 环境信息${NC}"
if command -v mvn &> /dev/null; then
    MVN_VERSION=$(mvn -v | head -1)
    echo -e "${GREEN}✓${NC} Maven 已安装: ${MVN_VERSION}"
    mvn -v
else
    echo -e "${RED}✗${NC} Maven 未安装"
    ((ISSUES_FOUND++))
fi

################################################################################
# 2. Java 环境信息
################################################################################
echo -e "\n${BLUE}[2/10] Java 环境信息${NC}"
if command -v java &> /dev/null; then
    JAVA_VERSION=$(java -version 2>&1 | head -1)
    echo -e "${GREEN}✓${NC} Java 已安装: ${JAVA_VERSION}"
    java -version 2>&1
else
    echo -e "${RED}✗${NC} Java 未安装"
    ((ISSUES_FOUND++))
fi

################################################################################
# 3. Maven Settings 配置检查
################################################################################
echo -e "\n${BLUE}[3/10] Maven Settings 配置检查${NC}"

# 检查 settings.xml 位置
SETTINGS_LOCATIONS=(
    "$HOME/.m2/settings.xml"
    "/etc/maven/settings.xml"
    "$M2_HOME/conf/settings.xml"
)

SETTINGS_FOUND=false
for location in "${SETTINGS_LOCATIONS[@]}"; do
    if [ -f "$location" ]; then
        echo -e "${GREEN}✓${NC} 找到 settings.xml: $location"
        SETTINGS_FOUND=true
        
        # 检查镜像配置
        if grep -q "<mirrors>" "$location"; then
            echo "  镜像配置:"
            grep -A 5 "<mirror>" "$location" | grep "<url>" | head -3
        else
            echo -e "  ${YELLOW}⚠${NC} 未配置镜像"
        fi
        
        # 检查仓库配置
        if grep -q "<repositories>" "$location"; then
            echo "  仓库配置:"
            grep -A 5 "<repository>" "$location" | grep "<url>" | head -3
        fi
        
        break
    fi
done

if [ "$SETTINGS_FOUND" = false ]; then
    echo -e "${RED}✗${NC} 未找到 settings.xml"
    echo "  提示: 请在 CI Pipeline 中配置 settings.xml"
    ((ISSUES_FOUND++))
fi

# 显示有效配置
echo -e "\n  有效 Maven 配置:"
if command -v mvn &> /dev/null; then
    mvn help:effective-settings 2>/dev/null | grep -A 3 "<mirrors>\|<repositories>" | head -20 || true
fi

################################################################################
# 4. pom.xml 检查
################################################################################
echo -e "\n${BLUE}[4/10] pom.xml 检查${NC}"

if [ -f "pom.xml" ]; then
    echo -e "${GREEN}✓${NC} pom.xml 存在"
    
    # 检查依赖声明
    if grep -q "<dependencies>" pom.xml; then
        echo -e "${GREEN}✓${NC} 找到 <dependencies> 标签"
        
        # 搜索特定依赖
        if grep -i -q "$DEPENDENCY_NAME" pom.xml; then
            echo -e "${GREEN}✓${NC} 找到 ${DEPENDENCY_NAME} 依赖声明:"
            grep -B 1 -A 5 -i "$DEPENDENCY_NAME" pom.xml | head -20
        else
            echo -e "${RED}✗${NC} 未找到 ${DEPENDENCY_NAME} 依赖声明"
            echo "  提示: 请在 pom.xml 中显式声明该依赖"
            ((ISSUES_FOUND++))
        fi
    else
        echo -e "${YELLOW}⚠${NC} 未找到 <dependencies> 标签"
    fi
    
    # 检查 parent POM
    if grep -q "<parent>" pom.xml; then
        echo -e "\n  Parent POM:"
        grep -A 5 "<parent>" pom.xml | head -10
    fi
    
else
    echo -e "${RED}✗${NC} pom.xml 不存在"
    ((ISSUES_FOUND++))
fi

################################################################################
# 5. 依赖树分析
################################################################################
echo -e "\n${BLUE}[5/10] 依赖树分析${NC}"

if [ -f "pom.xml" ] && command -v mvn &> /dev/null; then
    echo "  生成依赖树..."
    
    if mvn dependency:tree -DoutputFile=dependency-tree.txt 2>/dev/null; then
        echo -e "${GREEN}✓${NC} 依赖树生成成功"
        
        # 搜索特定依赖
        if grep -i -q "$DEPENDENCY_NAME" dependency-tree.txt; then
            echo -e "${GREEN}✓${NC} 在依赖树中找到 ${DEPENDENCY_NAME}:"
            grep -i "$DEPENDENCY_NAME" dependency-tree.txt | head -10
        else
            echo -e "${RED}✗${NC} 依赖树中未找到 ${DEPENDENCY_NAME}"
            echo "  提示: 该依赖可能未被正确解析"
            ((ISSUES_FOUND++))
        fi
        
        # 检查冲突
        if grep -q "omitted for conflict" dependency-tree.txt; then
            echo -e "\n  ${YELLOW}⚠${NC} 发现版本冲突:"
            grep "omitted for conflict" dependency-tree.txt | head -5
        fi
    else
        echo -e "${RED}✗${NC} 依赖树生成失败"
        ((ISSUES_FOUND++))
    fi
else
    echo -e "${YELLOW}⚠${NC} 跳过（pom.xml 或 mvn 不可用）"
fi

################################################################################
# 6. 网络连通性检查
################################################################################
echo -e "\n${BLUE}[6/10] 网络连通性检查${NC}"

# Maven Central
echo "  检查 Maven Central..."
if curl -s -o /dev/null -w "%{http_code}" "https://repo1.maven.org/maven2/" | grep -q "200"; then
    echo -e "${GREEN}✓${NC} Maven Central 可访问 (https://repo1.maven.org/maven2/)"
else
    echo -e "${RED}✗${NC} Maven Central 不可访问"
    echo "  提示: 检查网络连接或代理配置"
    ((ISSUES_FOUND++))
fi

# 检查 settings.xml 中配置的仓库
if [ "$SETTINGS_FOUND" = true ]; then
    for location in "${SETTINGS_LOCATIONS[@]}"; do
        if [ -f "$location" ]; then
            REPO_URLS=$(grep -oP '(?<=<url>)[^<]+' "$location" | grep -E '^https?://' | head -3)
            if [ -n "$REPO_URLS" ]; then
                echo -e "\n  检查配置的仓库:"
                while IFS= read -r url; do
                    if curl -s -o /dev/null -w "%{http_code}" "$url" | grep -q "200\|301\|302"; then
                        echo -e "  ${GREEN}✓${NC} $url"
                    else
                        echo -e "  ${RED}✗${NC} $url (不可访问)"
                        ((ISSUES_FOUND++))
                    fi
                done <<< "$REPO_URLS"
            fi
            break
        fi
    done
fi

################################################################################
# 7. 本地仓库缓存检查
################################################################################
echo -e "\n${BLUE}[7/10] 本地仓库缓存检查${NC}"

LOCAL_REPO="$HOME/.m2/repository"
if [ -d "$LOCAL_REPO" ]; then
    CACHE_SIZE=$(du -sh "$LOCAL_REPO" 2>/dev/null | cut -f1)
    echo -e "${GREEN}✓${NC} 本地仓库存在: $LOCAL_REPO"
    echo "  缓存大小: $CACHE_SIZE"
    
    # 检查特定依赖缓存
    DEPENDENCY_CACHE=$(find "$LOCAL_REPO" -type d -iname "*${DEPENDENCY_NAME}*" 2>/dev/null | head -5)
    if [ -n "$DEPENDENCY_CACHE" ]; then
        echo -e "${GREEN}✓${NC} 找到 ${DEPENDENCY_NAME} 缓存:"
        echo "$DEPENDENCY_CACHE"
    else
        echo -e "${YELLOW}⚠${NC} 未找到 ${DEPENDENCY_NAME} 缓存"
    fi
else
    echo -e "${YELLOW}⚠${NC} 本地仓库不存在: $LOCAL_REPO"
    echo "  提示: 首次构建或缓存已清理"
fi

################################################################################
# 8. 环境变量检查
################################################################################
echo -e "\n${BLUE}[8/10] 环境变量检查${NC}"

ENV_VARS=(
    "MAVEN_OPTS"
    "MAVEN_HOME"
    "M2_HOME"
    "JAVA_HOME"
    "http_proxy"
    "https_proxy"
)

for var in "${ENV_VARS[@]}"; do
    if [ -n "${!var}" ]; then
        echo -e "${GREEN}✓${NC} $var = ${!var}"
    else
        echo "  $var = (未设置)"
    fi
done

################################################################################
# 9. 尝试下载依赖
################################################################################
echo -e "\n${BLUE}[9/10] 尝试下载依赖${NC}"

if [ -f "pom.xml" ] && command -v mvn &> /dev/null; then
    # 从 pom.xml 提取依赖信息
    DEPENDENCY_INFO=$(grep -B 1 -A 4 -i "$DEPENDENCY_NAME" pom.xml | grep -E "groupId|artifactId|version" | head -6)
    
    if [ -n "$DEPENDENCY_INFO" ]; then
        GROUP_ID=$(echo "$DEPENDENCY_INFO" | grep "groupId" | sed 's/.*<groupId>\(.*\)<\/groupId>.*/\1/' | tr -d ' ')
        ARTIFACT_ID=$(echo "$DEPENDENCY_INFO" | grep "artifactId" | sed 's/.*<artifactId>\(.*\)<\/artifactId>.*/\1/' | tr -d ' ')
        VERSION=$(echo "$DEPENDENCY_INFO" | grep "version" | sed 's/.*<version>\(.*\)<\/version>.*/\1/' | tr -d ' ')
        
        if [ -n "$GROUP_ID" ] && [ -n "$ARTIFACT_ID" ] && [ -n "$VERSION" ]; then
            echo "  尝试下载: $GROUP_ID:$ARTIFACT_ID:$VERSION"
            
            if mvn dependency:get -Dartifact="$GROUP_ID:$ARTIFACT_ID:$VERSION" -Dtransitive=false 2>&1 | tee /tmp/mvn-download.log; then
                if grep -q "BUILD SUCCESS" /tmp/mvn-download.log; then
                    echo -e "${GREEN}✓${NC} 依赖下载成功"
                else
                    echo -e "${RED}✗${NC} 依赖下载失败"
                    ((ISSUES_FOUND++))
                fi
            else
                echo -e "${RED}✗${NC} 依赖下载失败"
                ((ISSUES_FOUND++))
            fi
        else
            echo -e "${YELLOW}⚠${NC} 无法提取完整的依赖信息"
        fi
    else
        echo -e "${YELLOW}⚠${NC} 未找到依赖信息"
    fi
else
    echo -e "${YELLOW}⚠${NC} 跳过（pom.xml 或 mvn 不可用）"
fi

################################################################################
# 10. 编译测试
################################################################################
echo -e "\n${BLUE}[10/10] 编译测试${NC}"

if [ -f "pom.xml" ] && command -v mvn &> /dev/null; then
    echo "  运行 mvn compile..."
    
    if mvn clean compile -X 2>&1 | tee /tmp/mvn-compile.log; then
        if grep -q "BUILD SUCCESS" /tmp/mvn-compile.log; then
            echo -e "${GREEN}✓${NC} 编译成功"
        else
            echo -e "${RED}✗${NC} 编译失败"
            echo -e "\n  错误摘要:"
            grep -i "error\|failed" /tmp/mvn-compile.log | head -10
            ((ISSUES_FOUND++))
        fi
    else
        echo -e "${RED}✗${NC} 编译失败"
        ((ISSUES_FOUND++))
    fi
    
    # 检查特定错误
    if grep -i -q "package.*does not exist" /tmp/mvn-compile.log; then
        echo -e "\n  ${RED}✗${NC} 发现 'package does not exist' 错误:"
        grep -i "package.*does not exist" /tmp/mvn-compile.log | head -5
    fi
else
    echo -e "${YELLOW}⚠${NC} 跳过（pom.xml 或 mvn 不可用）"
fi

################################################################################
# 诊断总结
################################################################################
echo -e "\n========================================="
echo "诊断总结"
echo "========================================="

if [ $ISSUES_FOUND -eq 0 ]; then
    echo -e "${GREEN}✓ 未发现明显问题${NC}"
else
    echo -e "${RED}✗ 发现 $ISSUES_FOUND 个问题${NC}"
fi

echo -e "\n${BLUE}建议措施:${NC}"
echo "========================================="

if ! grep -i -q "$DEPENDENCY_NAME" pom.xml 2>/dev/null; then
    echo "1. ${RED}[关键]${NC} 在 pom.xml 中显式声明 ${DEPENDENCY_NAME} 依赖"
    echo "   示例:"
    echo "   <dependency>"
    echo "       <groupId>com.github.tomakehurst</groupId>"
    echo "       <artifactId>wiremock-jre8</artifactId>"
    echo "       <version>2.35.0</version>"
    echo "   </dependency>"
    echo ""
fi

if [ "$SETTINGS_FOUND" = false ]; then
    echo "2. ${RED}[关键]${NC} 配置 Maven settings.xml"
    echo "   在 CI Pipeline 中添加:"
    echo "   before_script:"
    echo "     - mkdir -p ~/.m2"
    echo "     - cp ci/settings.xml ~/.m2/settings.xml"
    echo ""
fi

echo "3. 检查依赖 scope 是否正确"
echo "   - 如果在 src/main 中使用，scope 应为 compile 或省略"
echo "   - 如果只在测试中使用，scope 可以是 test"
echo ""

echo "4. 对比本地和 CI 环境差异"
echo "   - Maven 版本"
echo "   - JDK 版本"
echo "   - settings.xml 配置"
echo "   - 网络访问权限"
echo ""

echo "5. 启用 CI 缓存以加速构建"
echo "   cache:"
echo "     paths:"
echo "       - .m2/repository/"
echo ""

echo "========================================="
echo "生成的文件:"
echo "========================================="
[ -f "dependency-tree.txt" ] && echo "- dependency-tree.txt (依赖树)"
[ -f "/tmp/mvn-download.log" ] && echo "- /tmp/mvn-download.log (下载日志)"
[ -f "/tmp/mvn-compile.log" ] && echo "- /tmp/mvn-compile.log (编译日志)"
echo ""

echo "========================================="
echo "参考文档:"
echo "========================================="
echo "- Maven 依赖机制: https://maven.apache.org/guides/introduction/introduction-to-dependency-mechanism.html"
echo "- Maven Settings: https://maven.apache.org/settings.html"
echo "- 平台文档: https://docs.platform.com/maven-troubleshooting"
echo "========================================="

# 返回状态码
if [ $ISSUES_FOUND -gt 0 ]; then
    exit 1
else
    exit 0
fi
