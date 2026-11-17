# 会话 Token 用量报告

> 数据来源：`~/.hermes/profiles/architecture/state.db` 的 `session_model_usage` 表
> 会话 ID：`local-eeb2063c161ea5023b3bf6b9d766fb5d5f56b813bf9a43a888087b2f17c806af`
> 统计时间：2026-11-01
>
> **口径说明**：本会话走 Anthropic 兼容端点（`https://api.minimaxi.com/anthropic`），
> 因此 `input_tokens` **只含未缓存部分**，
> `prompt_total = input_tokens + cache_read_tokens + cache_write_tokens`。

---

## 1. 总计

| 指标 | 数值 |
|---|---|
| **API 调用总数** | **300** |
| **prompt 总量** | **15,786,250** |
| ├ 未缓存输入 | 3,969,303 |
| ├ 缓存读取 | 11,816,947 |
| └ 缓存写入 | 0 |
| **输出总量** | **608,350** |
| **总 token（prompt + output）** | **16,394,600** |
| 工具调用次数 | 1,920 |
| 助手消息数 | 1,352 |
| 上下文压缩次数 | **51** |

### 缓存命中率

| 范围 | 命中率 |
|---|---|
| 主循环（MAIN） | **76.22%** |
| 全会话（含辅助任务） | **74.86%** |

---

## 2. 按任务拆分

| 任务 | API 调用 | 未缓存输入 | 缓存读取 | 输出 | prompt 合计 |
|---|---:|---:|---:|---:|---:|
| **主循环**（对话 + 工具） | 245 | 3,472,875 | 11,130,724 | 208,379 | 14,603,599 |
| **上下文压缩** | 40 | 348,606 | 0 | 379,606 | 348,606 |
| **后台自审**（background_review） | 14 | 147,544 | 686,223 | 20,160 | 833,767 |
| 标题生成 | 1 | 278 | 0 | 205 | 278 |
| **合计** | **300** | **3,969,303** | **11,816,947** | **608,350** | **15,786,250** |

---

## 3. 成本分布与诊断

### 3.1 主循环占 92.5%

```
主循环 prompt 合计 = 14,603,599  →  占全会话 92.5%
辅助任务 prompt 合计 = 1,182,651  →  占 7.5%
```

结论：**开销的主体是正常的主循环对话**，不是压缩或自审。

### 3.2 压缩是最大的单项浪费

| 项 | 数值 | 说明 |
|---|---|---|
| 压缩次数 | **51** | 远超健康值（单次长任务 < 10） |
| 压缩 API 调用 | 40 | 每次压缩一次 LLM 摘要调用 |
| 压缩输出 token | **379,606** | 全部是摘要文本，**零任务产物** |
| 压缩缓存读取 | **0** | 压缩调用**完全没命中缓存** |

**这是本次会话最明显的优化空间。**
压缩调用不享受缓存优惠（cache_read = 0），却要重发全量上下文，
产出的又只是摘要文本而非可用成果。

**根因**：单次任务被拆得过细 —— 每写一篇文档都伴随多轮
`read_file` / `search_files` / `web_extract`，把上下文迅速撑大，
触发了 51 次压缩。

**改进方向**（下次同类任务）：
1. 用 `delegate_task` 把「上游抓取 + 提取」隔离到子 agent，
   主上下文只留结论 → 可减少 30%+ 的上下文增长
2. 抓取前先读 `~/.hermes/profiles/architecture/cache/scratch/upstream-index.md`，
   命中本地就直接读，不重抓
3. 一次 `execute_code` 批量完成多文件提取，不逐个 grep
4. 优先 `proactive_prune_tokens`（免费、确定性），避免触发计费的 LLM 摘要压缩

### 3.3 background_review 是非必要开销

14 次调用 / 833,767 prompt token，占 5.3%。
按 SOUL 约定，用户没要求就不应触发。
本次这部分属于**可避免成本**。

---

## 4. 工具调用分布

| 工具 | 次数 | 占比 |
|---|---:|---:|
| `execute_code` | 1,617 | 84.2% |
| `write_file` | 78 | 4.1% |
| `read_file` | 59 | 3.1% |
| `search_files` | 46 | 2.4% |
| `web_extract` | 44 | 2.3% |
| `browser_exec` | 30 | 1.6% |
| `patch` | 16 | 0.8% |
| `terminal` | 15 | 0.8% |
| `skill_view` | 14 | 0.7% |

**平均每轮助手消息 1.42 次工具调用**，说明批量策略执行得不错
（大部分操作是单次 `execute_code` 里做多个事）。

但 `execute_code` 用了 1,617 次仍偏高 —— 配合 51 次压缩，
说明单次 execute_code 里的输出量仍然偏大，
每次输出都要在后续每一轮重新发送（乘数效应）。

---

## 5. 交付物与开销的对应关系

本次会话产出：

| 交付物 | 规模 |
|---|---|
| `ucp/argocd-topics/` 专题文档 | 11 篇（含 README），3,906 行 |
| `ucp/argocd-topics/examples/` | 7 个 YAML + 1 个 Shell 脚本，1,321 行 |
| `ucp/README.md` | 已更新（新增「当前有效方案」入口） |
| **合计** | **约 5,599 行 / 164 KB** |

对应开销：**约 16.4M token**（prompt 15.8M + output 0.6M）。

单 token 产出 ≈ 34 字符/token —— 对一个多轮工具型研究任务属正常区间，
但**压缩占比（输出 379,606 / 608,350 ≈ 62% 的输出 token 是摘要）**
说明仍有明显优化空间。

---

## 6. 结论与建议

| 结论 | 依据 |
|---|---|
| 主循环开销正常 | 占 prompt 总量 92.5%，缓存命中 76.22% |
| **压缩开销过高** | 51 次压缩，产出 379,606 token 纯摘要，缓存命中 0 |
| 后台自审可省 | 833,767 prompt token 属于非必要调用 |
| 工具调用粒度合理 | 平均 1.42 次/轮，批量策略有效 |
| 产出密度正常 | 约 5,600 行文档 / 16.4M token |

**下次同类任务的三个具体改进**：

1. 上游抓取与提取全部交给 `delegate_task` 子 agent，
   主上下文只接收结论表 —— 预计减少 30–40% 的主循环 prompt
2. 落盘前先查 `upstream-index.md`，命中即读本地，禁止重抓
3. 长文档写作按「一篇一次 write_file」推进，
   中间不做逐行 grep 校验，最后统一用一次 `execute_code` 批量校验

---

## 7. 复核命令

```bash
python3 - <<'PY'
import sqlite3
c = sqlite3.connect("/Users/lex/.hermes/profiles/architecture/state.db")
c.row_factory = sqlite3.Row
sid = "local-eeb2063c161ea5023b3bf6b9d766fb5d5f56b813bf9a43a888087b2f17c806af"
for r in c.execute("SELECT * FROM session_model_usage WHERE session_id=?", (sid,)):
    d = dict(r)
    print(d["task"] or "MAIN", d["api_call_count"], d["input_tokens"],
          d["cache_read_tokens"], d["output_tokens"])
PY
```
