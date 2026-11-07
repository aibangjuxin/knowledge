# CR Check —— 开发常用命令
APP      := cr-check
PKG      := ./...
CONFIG   ?= config/policy.yaml
ADDR     ?= :8080
LDFLAGS  := -s -w

.PHONY: help run build test lint fmt vet tidy clean docker

help: ## 显示可用命令
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

run: ## 本地起服务（mock 模式，同步判定，curl 立刻能看到结论）
	go run ./cmd/server -config $(CONFIG) -mode mock -addr $(ADDR) -sync-eval

run-real: ## 按真实凭据起服务（异步判定）
	go run ./cmd/server -config $(CONFIG) -mode real -addr $(ADDR)

show-config: ## 打印生效配置（脱敏）
	go run ./cmd/server -config $(CONFIG) -show-config

build: ## 编译到 bin/
	CGO_ENABLED=0 go build -trimpath -ldflags '$(LDFLAGS)' -o bin/$(APP) ./cmd/server

test: ## 跑测试
	go test -race -cover ./...

vet: ## 官方静态检查
	go vet ./...

lint: ## golangci-lint
	golangci-lint run ./...

fmt: ## 格式化 + 整理 import
	gofmt -w .
	goimports -w .

tidy: ## 清理依赖
	go mod tidy

clean: ## 清理
	rm -rf bin
	go clean -testcache

docker: ## 构建镜像
	docker build -t $(APP):dev .
