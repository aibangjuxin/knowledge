# Flow (Network Flow) 知识库

## 目录描述
本目录包含网络流量、请求流程、服务暴露和流量管理相关的知识。

## 目录结构
```
flow/
├── flow-nginx-enhance/           # Nginx流量增强相关内容
├── external-flow.md              # 外部流量相关
├── How-to-expose-gemini.md       # 如何暴露Gemini服务
├── How-to-expose-grok.md         # 如何暴露Grok服务
├── How-to-expose-internalservice.md # 如何暴露内部服务
├── How-to-get-route.md           # 如何获取路由
├── internal-flow.md              # 内部流量相关
├── L7-L4-request-flow.md         # 7层和4层请求流量
├── pub-ingress-flow.md           # 公共入口流量
└── README.md                     # 本说明文件
```

## 文件说明 (按功能分类)
### 流量类型
- `external-flow.md`: 外部流量处理
- `internal-flow.md`: 内部流量处理
- `L7-L4-request-flow.md`: 7层（HTTP）和4层（TCP/UDP）请求流量

### 服务暴露
- `How-to-expose-gemini.md`: 如何暴露Gemini AI服务
- `How-to-expose-grok.md`: 如何暴露Grok AI服务
- `How-to-expose-internalservice.md`: 如何暴露内部服务

### 路由和入口
- `How-to-get-route.md`: 路由获取方法
- `pub-ingress-flow.md`: 公共入口流量管理

### 流量增强
- `flow-nginx-enhance/`: Nginx流量增强相关内容

## 快速检索
- 内外流量: 查看 `internal-flow.md` 和 `external-flow.md`
- 服务暴露: 查看 `How-to-expose-*.md` 系列文件
- 路由管理: 查看 `How-to-get-route.md`
- 流量分层: 查看 `L7-L4-request-flow.md`
- Nginx增强: 查看 `flow-nginx-enhance/` 目录