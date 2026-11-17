# Java 认证扫描工具 Makefile

# 变量定义
PROJECT_NAME = auth-scanner
VERSION = 1.0.0
DOCKER_REGISTRY = your-registry
DOCKER_IMAGE = $(DOCKER_REGISTRY)/$(PROJECT_NAME):$(VERSION)
DOCKER_LATEST = $(DOCKER_REGISTRY)/$(PROJECT_NAME):latest

# Maven 相关
MVN = mvn
JAVA = java
JAR_FILE = target/$(PROJECT_NAME).jar

# 默认目标
.PHONY: help
help: ## 显示帮助信息
	@echo "Java 认证扫描工具构建命令："
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# 构建相关
.PHONY: clean
clean: ## 清理构建文件
	$(MVN) clean
	docker rmi $(DOCKER_IMAGE) $(DOCKER_LATEST) 2>/dev/null || true

.PHONY: compile
compile: ## 编译项目
	$(MVN) compile

.PHONY: test
test: ## 运行测试
	$(MVN) test

.PHONY: package
package: ## 打包 JAR 文件
	$(MVN) clean package -DskipTests

.PHONY: build
build: package ## 完整构建（包含测试）
	$(MVN) clean package

# Docker 相关
.PHONY: docker-build
docker-build: package ## 构建 Docker 镜像
	docker build -t $(DOCKER_IMAGE) -t $(DOCKER_LATEST) -f docker/Dockerfile .

.PHONY: docker-push
docker-push: docker-build ## 推送 Docker 镜像
	docker push $(DOCKER_IMAGE)
	docker push $(DOCKER_LATEST)

.PHONY: docker-run
docker-run: ## 运行 Docker 容器（需要指定 JAR_PATH）
	@if [ -z "$(JAR_PATH)" ]; then \
		echo "错误: 请指定 JAR_PATH，例如: make docker-run JAR_PATH=/path/to/app.jar"; \
		exit 1; \
	fi
	docker run --rm -v $(shell dirname $(JAR_PATH)):/workspace $(DOCKER_LATEST) /workspace/$(shell basename $(JAR_PATH))

# 测试和验证
.PHONY: test-scanner
test-scanner: package ## 测试扫描器功能
	@echo "创建测试 JAR 文件..."
	@mkdir -p test-data
	@echo "Manifest-Version: 1.0" > test-data/MANIFEST.MF
	@cd test-data && jar cfm test-app.jar MANIFEST.MF
	@echo "运行扫描测试..."
	$(JAVA) -jar $(JAR_FILE) test-data/test-app.jar --output test-data/scan-result.json
	@echo "扫描测试完成，结果保存在 test-data/scan-result.json"

.PHONY: integration-test
integration-test: docker-build ## 运行集成测试
	@echo "运行集成测试..."
	@mkdir -p test-data
	@echo "Manifest-Version: 1.0" > test-data/MANIFEST.MF
	@cd test-data && jar cfm integration-test.jar MANIFEST.MF
	docker run --rm -v $(PWD)/test-data:/workspace $(DOCKER_LATEST) /workspace/integration-test.jar
	@echo "集成测试完成"

# 部署相关
.PHONY: deploy-k8s
deploy-k8s: docker-push ## 部署到 Kubernetes
	@echo "部署到 Kubernetes..."
	kubectl apply -f examples/kubernetes-job.yaml
	@echo "部署完成，使用 'kubectl logs job/auth-scanner-job' 查看日志"

.PHONY: install-local
install-local: package ## 安装到本地
	@echo "安装扫描器到本地..."
	@mkdir -p ~/.local/bin
	@cp $(JAR_FILE) ~/.local/bin/$(PROJECT_NAME).jar
	@echo '#!/bin/bash' > ~/.local/bin/auth-scanner
	@echo 'java -jar ~/.local/bin/$(PROJECT_NAME).jar "$$@"' >> ~/.local/bin/auth-scanner
	@chmod +x ~/.local/bin/auth-scanner
	@echo "安装完成，使用 'auth-scanner' 命令运行"

# 开发相关
.PHONY: dev-setup
dev-setup: ## 设置开发环境
	@echo "设置开发环境..."
	$(MVN) dependency:resolve
	@echo "开发环境设置完成"

.PHONY: format
format: ## 格式化代码
	$(MVN) spotless:apply

.PHONY: lint
lint: ## 代码检查
	$(MVN) spotless:check
	$(MVN) checkstyle:check

# 文档相关
.PHONY: docs
docs: ## 生成文档
	$(MVN) javadoc:javadoc
	@echo "文档生成完成，查看 target/site/apidocs/index.html"

# 发布相关
.PHONY: release
release: clean test package docker-build ## 创建发布版本
	@echo "创建发布版本 $(VERSION)..."
	git tag -a v$(VERSION) -m "Release version $(VERSION)"
	@echo "发布版本 v$(VERSION) 创建完成"
	@echo "使用 'git push origin v$(VERSION)' 推送标签"
	@echo "使用 'make docker-push' 推送 Docker 镜像"

# 示例和演示
.PHONY: demo
demo: package ## 运行演示
	@echo "运行认证扫描器演示..."
	@echo "1. 创建示例应用..."
	@mkdir -p demo/src/main/java/com/example
	@cat > demo/src/main/java/com/example/SecurityConfig.java << 'EOF'
package com.example;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
@EnableWebSecurity
public class SecurityConfig {}
EOF
	@echo "2. 编译示例应用..."
	@cd demo && javac -cp . src/main/java/com/example/SecurityConfig.java
	@cd demo && jar cf demo-app.jar -C src/main/java .
	@echo "3. 运行扫描..."
	$(JAVA) -jar $(JAR_FILE) demo/demo-app.jar --output demo/scan-result.json
	@echo "4. 显示结果..."
	@cat demo/scan-result.json | jq '.'
	@echo "演示完成！"

# 清理演示文件
.PHONY: clean-demo
clean-demo: ## 清理演示文件
	rm -rf demo test-data

# 性能测试
.PHONY: benchmark
benchmark: package ## 运行性能基准测试
	@echo "运行性能基准测试..."
	@mkdir -p benchmark
	@for i in {1..10}; do \
		echo "创建测试 JAR $$i..."; \
		mkdir -p benchmark/test$$i; \
		echo "Manifest-Version: 1.0" > benchmark/test$$i/MANIFEST.MF; \
		cd benchmark/test$$i && jar cfm test$$i.jar MANIFEST.MF; \
		cd ../..; \
	done
	@echo "开始基准测试..."
	@time for jar in benchmark/test*/test*.jar; do \
		$(JAVA) -jar $(JAR_FILE) $$jar > /dev/null 2>&1; \
	done
	@echo "基准测试完成"
	@rm -rf benchmark

# 全面检查
.PHONY: check-all
check-all: clean compile test lint package integration-test ## 运行所有检查
	@echo "所有检查完成 ✅"

# 快速构建（跳过测试）
.PHONY: quick-build
quick-build: ## 快速构建（跳过测试）
	$(MVN) clean package -DskipTests -Dcheckstyle.skip=true -Dspotless.check.skip=true