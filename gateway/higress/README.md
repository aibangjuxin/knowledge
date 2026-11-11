# Higress 知识库

## 目录描述

本目录包含 Higress（基于 Istio + Envoy 的云原生 AI 网关 / API 网关，CNCF Sandbox 项目）的知识文档。

## 目录结构

```
higress/
├── Higress.md              # 主文档：架构、场景、插件生态、部署、对比与选型
└── README.md               # 本说明文件
```

## 文件说明

- `Higress.md`：Higress 全景文档，包含
  - 项目档案与合规身份（CNCF Sandbox / Gateway API Conformant / GIE 实现）
  - 架构与组件（higress-controller / higress-gateway / higress-console）
  - 四大使用场景：AI Gateway、MCP Server 托管、K8s Ingress/Gateway API、微服务与安全网关
  - 插件生态（AI Provider / Consumer / Dev、认证、安全、流量）与支持模型厂商清单
  - 快速上手（Docker / Helm / hgctl）、关键 Helm 参数
  - 关键配置模型（WasmPlugin CRD、McpBridge CRD、插件三级优先级）
  - 实战示例（Vertex AI 代理、Token 级限流、AI 统计落日志、模型映射）
  - 与 Nginx / Spring Cloud Gateway / Envoy Gateway / Tengine / Kong 的对比
  - 在 GKE 上的部署注意事项与本仓库其它方案的选型关系

## 快速检索

- 什么是 Higress → `Higress.md` 第 1、2 节
- 架构与组件 → `Higress.md` 第 3 节
- 插件清单 / 支持哪些模型 → `Higress.md` 第 6 节
- 安装部署 → `Higress.md` 第 7 节
- CRD 与配置模型 → `Higress.md` 第 8 节
- YAML 示例 → `Higress.md` 第 9 节
- 与 Kong / Nginx / GKE Gateway 怎么选 → `Higress.md` 第 10、11 节
- 已知限制与坑 → `Higress.md` 第 13 节

## 相关目录

- `../kong/`：Kong API 网关相关文档
- `../no-gateway/`：无网关（直连）方案对比
- `../docs/Design.md`：平台接入类型分类（Kong / GKE Gateway / No-Gateway / Container）
