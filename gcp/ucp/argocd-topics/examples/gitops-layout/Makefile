# =============================================================================
#  gitops-layout/Makefile —— 这个仓库的统一入口
# -----------------------------------------------------------------------------
#  为什么要它：
#    这个仓库有 12 个检查/脚手架工具、12 种调用方式。新人记不住，
#    CI 也得在 workflow 里抄一遍参数。Makefile 把它们收口成**一个入口**：
#      make help          看所有命令
#      make ci            跑全部检查（提交前 / CI 都跑这个）
#      make ci-quick      跳过需要 kubectl 的（没装 kubectl 也能跑）
#      make preview       看看会生成哪些 Application
#      make render        渲染所有 overlay（kubectl kustomize build）
#      make bootstrap     验证根应用能不能 build
#      make sync          触发 Argo CD 同步（必须显式给 APP 和 REV）
#      make doctor        Argo CD 集群体检（只读）
#
#  集群纳管（fleet）：
#      make new-cluster   加一个集群（生成 YAML，不碰凭据）
#      make enable-comp   给集群加一个组件
#      make cluster-check 集群清单自检
#      make fleet-list    集群 × 组件矩阵
#      make fleet-drift   ★ 对账：Git 声明 vs Argo CD 实际注册
#
#  设计原则（和 daydayup/Makefile 一致）：
#    ① .DEFAULT_GOAL := help  —— 敲 make 不该误触发任何有副作用的事
#    ② 工具不在就降级并说明  —— 不因为没装 helm 就整个失败
#    ③ 变量用 ?=            —— 本地与 CI 可以各自覆盖
#    ④ 有副作用的目标一律 .PHONY
# =============================================================================

SHELL        := /bin/bash
PY           ?= python3
KUBECTL      ?= kubectl
ARGOCD       ?= argocd
HELM         ?= helm

# 目录（脚本自己算的，这里保持一致）
LAYOUT_DIR   := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
EXAMPLES_DIR := $(abspath $(LAYOUT_DIR)/..)
TOPICS_DIR   := $(abspath $(EXAMPLES_DIR)/..)

# 动态发现
APPS         := $(sort $(notdir $(wildcard $(LAYOUT_DIR)/apps/*)))
OVERLAYS     := $(wildcard $(LAYOUT_DIR)/apps/*/overlays/*/kustomization.yaml)

.DEFAULT_GOAL := help

# ★ 生成物中途失败不要留半成品
.DELETE_ON_ERROR:
# ★ 涉及共享状态的目标不要并行
.NOTPARALLEL: sync render-all

.PHONY: help ci ci-quick lint preview docs-check render render-all bootstrap \
        sync status doctor apps clean \
        new-cluster enable-comp cluster-check fleet-list fleet-drift

help: ## 显示所有命令
	@echo "gitops-layout —— 统一入口"
	@echo ""
	@echo "── 检查 ─────────────────────────────────────────────"
	@echo "  make ci            跑全部检查（11 项）"
	@echo "  make ci-quick      跳过需要 kubectl 的检查"
	@echo "  make lint          只跑配置/规则契约检查（不需要 kubectl）"
	@echo "  make preview       预览会生成哪些 Application"
	@echo "  make docs-check    检查文档链接与锚点"
	@echo "  make render        渲染所有 overlay 并丢弃输出"
	@echo "  make bootstrap     验证根应用能不能 build"
	@echo ""
	@echo "── Argo CD ──────────────────────────────────────────"
	@echo "  make sync          同步（用法：make sync APP=api-prod REV=<sha>）"
	@echo "  make status        看应用状态（用法：make status APP=api-prod）"
	@echo "  make doctor        Argo CD 集群体检（只读）"
	@echo ""
	@echo "── 集群纳管 ─────────────────────────────────────────"
	@echo "  make new-cluster   加集群（加 DRY_RUN=1 只预览不落盘）"
	@echo "                        PROJECT=acme-dev SERVER=https://... COMPONENTS=\"nginx api\""
	@echo "  make enable-comp   加组件：make enable-comp CLUSTER=dev-03 COMPONENT=nginx"
	@echo "  make cluster-check 集群清单 + AppSet 一致性自检"
	@echo "  make fleet-list    集群 × 组件矩阵"
	@echo "  make fleet-drift   ★ 对账：Git 声明 vs Argo CD 实际注册"
	@echo ""
	@echo "可用 APP: $(APPS)"

# ── 检查 ────────────────────────────────────────────────────────────────────
ci: ## 跑全部检查
	@./ci-check.sh

ci-quick: ## 跳过需要 kubectl 的检查
	@./ci-check.sh --quick

lint: ## 只跑不需要 kubectl 的检查
	@$(PY) "$(EXAMPLES_DIR)/validate-examples.py"
	@$(PY) "$(EXAMPLES_DIR)/rulesets/validate-rulesets.py"
	@$(PY) "$(EXAMPLES_DIR)/rulesets/simulate-commit-gate.py" --all
	@$(PY) "$(EXAMPLES_DIR)/check-doc-links.py" --path "$(TOPICS_DIR)"

preview: ## 预览会生成哪些 Application
	@$(PY) "$(LAYOUT_DIR)/preview-appset.py"

docs-check: ## 检查文档链接与锚点
	@$(PY) "$(EXAMPLES_DIR)/check-doc-links.py" --path "$(TOPICS_DIR)"

# ── 渲染 ────────────────────────────────────────────────────────────────────
render: ## 渲染所有 overlay（只验证，不落盘）
ifeq ($(KUBECTL),)
	@echo "✗ 没有 kubectl"; exit 1
endif
	@for f in $(OVERLAYS); do \
		echo "── $$f"; \
		$(KUBECTL) kustomize "$$(dirname $$f)" > /dev/null || exit 1; \
	done

render-all: ## 渲染所有 overlay 并打印产物
	@for f in $(OVERLAYS); do \
		echo "── $$f"; \
		$(KUBECTL) kustomize "$$(dirname $$f)" || exit 1; \
	done

bootstrap: ## 验证根应用能 build
	@$(KUBECTL) kustomize "$(LAYOUT_DIR)/bootstrap" > /dev/null && echo "✓ bootstrap 可以 build"

apps: ## 列出应用
	@for a in $(APPS); do echo "  $$a"; done

# ── Argo CD ─────────────────────────────────────────────────────────────────
# ★ 同步必须显式给 APP 和 REV：绝不"同步到最新"。
#   理由见 gh-enterprise/23（driver 的幂等键 = app + revision）。
sync: ## 同步（make sync APP=api-prod REV=<sha>）
ifeq ($(APP),)
	@echo "用法: make sync APP=<name> REV=<sha>"; exit 1
endif
ifeq ($(REV),)
	@echo "★ 必须显式指定 REV（不要同步到 latest）"; exit 1
endif
	@$(ARGOCD) app sync "$(APP)" --revision "$(REV)" --prune=false

status: ## 看应用状态（make status APP=api-prod）
ifeq ($(APP),)
	@echo "用法: make status APP=<name>"; exit 1
endif
	@$(ARGOCD) app get "$(APP)" --core

doctor: ## Argo CD 集群体检（只读）
	@bash "$(EXAMPLES_DIR)/argocd-health.sh"

# ── 集群纳管（fleet）──────────────────────────────────────────────────────────
# ★ 这些目标只生成**声明**（YAML），绝不碰凭据。
#   Cluster Secret 含凭据 → 必须手工在 Argo CD 里注册（见 new-cluster.sh 第 ④ 步）。
new-cluster: ## 加集群（make new-cluster NAME=dev-03 ENV=dev PROJECT=... SERVER=... COMPONENTS="nginx api"）
ifeq ($(NAME),)
	@echo "用法: make new-cluster NAME=<cluster> ENV=<dev|stg|prod> PROJECT=<gcp-project> SERVER=<url> [COMPONENTS=\"a b\"]"; exit 1
endif
ifeq ($(ENV),)
	@echo "★ 必须指定 ENV（dev/stg/prod）"; exit 1
endif
ifeq ($(SERVER),)
	@echo "★ 必须指定 SERVER（Kubernetes API 地址，必须与 Cluster Secret 一致）"; exit 1
endif
	@args=""; for c in $(COMPONENTS); do args="$$args --component $$c"; done; \
	"$(LAYOUT_DIR)/new-cluster.sh" \
		--name "$(NAME)" \
		--env "$(ENV)" \
		$(if $(PROJECT),--project "$(PROJECT)",) \
		--server "$(SERVER)" \
		$(if $(NAMESPACE),--namespace "$(NAMESPACE)",) \
		$(if $(DRY_RUN),--dry-run,) \
		$$args

enable-comp: ## 加组件（make enable-comp CLUSTER=dev-03 COMPONENT=nginx）
ifeq ($(CLUSTER),)
	@echo "用法: make enable-comp CLUSTER=<name> COMPONENT=<component>"; exit 1
endif
ifeq ($(COMPONENT),)
	@echo "用法: make enable-comp CLUSTER=<name> COMPONENT=<component>"; exit 1
endif
	@"$(LAYOUT_DIR)/enable-component.sh" --cluster "$(CLUSTER)" --component "$(COMPONENT)" $(if $(DRY_RUN),--dry-run,)

cluster-check: ## 集群清单 + AppSet 一致性自检
	@$(PY) "$(LAYOUT_DIR)/validate-clusters.py"
	@$(PY) "$(LAYOUT_DIR)/appset-simulator.py" | tail -20

fleet-list: ## 集群 × 组件矩阵
	@$(PY) "$(LAYOUT_DIR)/fleet.py" list

fleet-drift: ## ★ 对账：Git 声明 vs Argo CD 实际注册（FLEET_STRICT=1 时有差异即失败）
	@$(PY) "$(LAYOUT_DIR)/fleet.py" drift $(if $(FLEET_STRICT),--strict,)

clean: ## 清理临时产物
	@rm -rf .tmp out
