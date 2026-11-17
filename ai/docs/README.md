# AI (Artificial Intelligence) 知识库

## 目录描述
本目录包含关于人工智能、AI代理、提示工程、OCR、Embedding 模型、本地 LLM 推理等相关知识和实践记录。

## 目录结构
```
ai/
├── agent-tree.md                       # AI代理树结构相关知识
├── ai-agent.md                         # AI代理相关概念和实践
├── prompt.md                           # 提示工程相关知识
├── Python-ocr.md                       # Python OCR 实践笔记
├── debug-ollama.md                     # Ollama 调试技巧
├── ollama.md                           # Ollama 综合使用笔记
├── ollama-warmup-pattern.md            # Ollama /v1/embeddings 冷启动 hang 的 warmup 防御模式
├── embedder-batch-size-tuning.md       # Embedder batch_size 调优 (32→40) 实测数据
├── llam-server.md                      # llama-server (llama.cpp) 本地推理笔记
├── chunk_size_overlap_batch_size_explorer.md  # chunk/batch/context 关系探索 + 文件大小决策树
├── .claude/                            # Claude相关配置或工具
└── README.md                           # 本说明文件
```

## 文件说明
- `agent-tree.md`: 记录AI代理的层级结构和关系
- `ai-agent.md`: AI代理的详细概念、实现和应用
- `prompt.md`: 提示工程的最佳实践和技巧
- `Python-ocr.md`: Python OCR 库选型与实践
- `debug-ollama.md`: Ollama 常见问题排查
- `ollama.md`: Ollama 综合使用笔记
- `ollama-warmup-pattern.md`: **macOS sleep-wake 后** `/v1/embeddings` hang bug 的3层防御(warmup + retry + timeout)
- `embedder-batch-size-tuning.md`: `embeddinggemma:300m` 长 batch 负载下 batch_size 调优实测,推荐 `32→40`
- `llam-server.md`: llama.cpp `llama-server` 本地推理笔记(对比 Ollama)
- `chunk_size_overlap_batch_size_explorer.md`: **三参数关系可视化**(context window / chunk / batch),文件大小 → 配置推荐决策树,含100KB/200KB/500KB/1MB 具体数字推导

## 快速检索
- AI代理相关: 查看 `ai-agent.md` 和 `agent-tree.md`
- 提示工程: 查看 `prompt.md`
- 本地 LLM / Embedding 部署: 查看 `ollama.md` + `debug-ollama.md`
- Embedding 模型稳定性: 查看 `ollama-warmup-pattern.md`(cold-start)+ `embedder-batch-size-tuning.md`(稳态吞吐)
- OCR: 查看 `Python-ocr.md`

## 相关 Skill / 仓库
- 配套 RAG 实现: `~/git/rag/` (基于 Ollama 的本地 RAG pipeline)
- 实测脚本: `~/git/rag/scripts/probe_embedder_batch.py`(batch_size 调优) + `scripts/probe_chunk_tokens.py`(corpus token 分布)