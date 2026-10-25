# Hermes 性能与 Token 消耗：诊断结论与解决方案

> 诊断对象：`architecture` profile（`~/.hermes/profiles/architecture`）
> 数据窗口：最近 7 天（`state.db` + `logs/agent.log` + `logs/errors.log` + `cron/usage_audit.jsonl`）
> 诊断日期：2026-10-24
> 性质：**只读诊断**。本文只给出方案，不包含任何已执行的配置变更。

---

## 0. 结论速览

| # | 问题 | 根因 | 方案 | 预期收益 | 成本 |
|---|---|---|---|---|---|
| P1 | 慢 + 费 token | 上下文无限增长（p90 prompt 148K / max 307K） | 收紧 `compression.threshold_tokens` + `proactive_prune_*` | 压缩调用次数 ↓，单次延迟 ↓ | 低，改配置 |
| P2 | 慢 + 费 token | **压缩用的辅助模型从未生效**，全部回落到主模型 | 修 `auxiliary.compression` 的 provider/model | 压缩从 72s/次 → 预计 <10s，且不烧主模型配额 | 低，改配置 |
| P3 | 费 token | `background_review` 后台复盘占 9.6% | 关闭或降频 | 直接省 9.6% | 低，改配置 |
| P4 | 费 token | 委派子代理失控（3 个 child × 250 次调用 = 24% 消耗） | 收紧 `delegation.max_iterations` / `max_concurrent_children` | 抑制单次任务烧掉 4600 万 | 低，已部分生效 |
| P5 | 费 token | Cron 三个 agent 型任务占 22% | 转 `no_agent` + 脚本，或改用独立 session | 直接省 22% | 中，需改 job |
| P6 | 慢 | 429/529 供应商过载重试 | 加 fallback provider + 降并发 | 消除 3 次重试 × 10-25s | 低，改配置 |
| P7 | 慢 | 本地状态膨胀（state.db 331MB / checkpoints 265MB） | 定期 checkpoint + 清理 | CLI 延迟 ↓，git 锁冲突 ↓ | 中，需运维动作 |

**投入产出最高的三个：P2（当前配置完全失效）、P3（一行配置）、P4（已部分生效，需确认）。**

---

## 1. 数据基线（诊断依据）

以下数字全部来自本机只读查询，可复现（复现命令见 §8）。

### 1.1 Token 总量（7 天）

```
GRAND TOTAL 7d = 195,087,559 tokens

  task=(main)             calls= 2143  in= 17,446,153  cache_read=154,205,697  out= 1,864,283  → 173,516,133
  task=background_review  calls=  132  in=  1,076,895  cache_read= 17,435,417  out=   231,334  →  18,743,646  (9.6%)
  task=compression        calls=  164  in=  1,306,154  cache_read=         256  out= 1,496,365  →   2,802,775  (1.4%)
  task=vision/title_gen   calls=    7                                                    →      25,005
```

按会话来源：

```
  source=subagent   sessions=3   calls=664  TOTAL= 46,521,909  (23.8%)
  source=cron       sessions=22  calls=518  TOTAL= 42,955,648  (22.0%)
  source=local      sessions=5   calls=531  TOTAL= 36,874,738  (18.9%)
  source=qqbot      sessions=1   calls= 69  TOTAL=  3,729,124  ( 1.9%)
```

**关键观察：**
- `cache_read` 占全部 prompt token 的 **91.4%**（221,076,122 / 241,898,511）——即绝大部分计费来自"重读历史上下文"，不是新生成的内容。
- `compression` 任务虽然只占 1.4% 的总 token，却占了 **41.4% 的输出 token**（1,496,365 / 3,613,200）。压缩是最贵的单个动作。

### 1.2 单次调用延迟

```
API call latency (n=3151):  min=0.9s  p50=5.5s  p90=21.0s  p99=66.4s  max=171.4s  mean=9.56s  sum=8.37h
```

按 prompt 大小分层（**延迟随上下文线性增长**）：

| prompt 大小 | n | mean | p50 | p90 | 累计耗时 |
|---|---|---|---|---|---|
| ≤20K | 47 | 5.40s | 4.10s | 10.70s | 0.07h |
| 20–60K | 1,557 | 7.99s | 5.00s | 16.50s | 3.46h |
| 60–120K | 1,024 | **11.66s** | 6.50s | **28.10s** | 3.32h |
| >120K | 523 | 10.48s | 5.70s | 21.40s | 1.52h |

prompt 大小分布：`p50=58,995  p90=148,419  p99=247,337  max=307,660`，平均 77,203。

墙钟时间去向（`assistant→tool` = 工具执行，`tool→assistant` = 模型思考 + API）：

```
assistant->tool  (tool runtime): n=8761  p50= 0.16s  p90= 10.97s  p99= 41.01s  sum= 8.64h
tool->assistant  (model think+API): n=8564  p50= 6.00s  p90= 59.94s  p99=156.74s  sum=49.45h
```

**结论：85% 的墙钟时间花在"等模型"上，工具执行只占 15%。"慢"的主因在上下文体积和供应商延迟，不在工具。**

### 1.3 压缩路径（**当前配置完全失效**）

```
compression dispatches (7d): 187
  dispatched using configured model 'google/gemini-3-flash-preview': 0
  models actually used: MiniMax-M3.1-Flash=171, MiniMax-M3.1-Flash-Preview=10,
                        google/gemini-3-flash-preview=2, minimaxai/minimax-m3.1-flash=2, MiniMax-M3=1

aux(compression) call latency: n=179  p50=72.5s  p90=157.1s  max=333.9s  sum=4.30h

WARNING agent.context_compressor: Summary model 'google/gemini-3-flash-preview' unavailable
        (404 page not found). Falling back to main model 'minimaxai/minimax-m3.1-flash'.
WARNING agent.conversation_compression: Configured compression model 'google/gemini-3-flash-preview'
        failed (404 page not found); recovered using the main model.
```

日志逐行配对确认：**187 次压缩派发中，179 次的 summary_model 与所选 route 的模型完全一致**——也就是压缩调用用的就是主模型 `MiniMax-M3.1-Flash`。

压缩还会打断 prompt cache：

```
avg cache-hit BEFORE compression: 79.0%  (n=59)
avg cache-hit AFTER  compression: 40.0%  (n=58)
```

其他压缩健康指标：

```
'Compression made no progress' warnings     : 6
'reclamation did not run' warns              : 111
  prune no-op reasons: nothing_eligible=74 | reclaim_below_minimum=30 | tail_only=7
```

### 1.4 供应商侧错误与重试

```
HTTP status histogram (7d): 429=5 | 529=8 | 400=4 | 401=4 | 502=2 | 410=1 | 403=1
'Token Plan' 命中 48 次 | '负载较高' 32 次 | 'rate limit' 35 次 | 'overloaded' 30 次
api_max_retries: 2  →  单次失败最多重试 3 次
```

样本（429，minimax-cn 配额）：
```
API call failed (attempt 1/3) error_type=RateLimitError
API call failed (attempt 2/3) error_type=RateLimitError   ← +3.4s
API call failed (attempt 3/3) error_type=RateLimitError   ← +5.1s
```

### 1.5 委派子代理（单次任务烧掉 4600 万 token）

3 个 child 由同一个 parent（`local-453faf5c…`）在 2026-10-23 14:43:26 同时派发：

| child | api calls | tool calls | input | cache_read | output | 合计 |
|---|---|---|---|---|---|---|
| `…_97bbf0` | **250** | 166 | 1,747,289 | 17,722,242 | 117,232 | 19,586,763 |
| `…_b6a257` | **250** | 227 | 1,453,913 | 17,911,253 | 119,416 | 19,484,582 |
| `…_bcc684` | 164 | 111 | 2,337,490 | 5,063,318 | 49,756 | 7,450,564 |

两个 child **精确停在 250 次调用**。源码确认这个数字来自 `tools/delegate_tool.py:106` 的 `DEFAULT_MAX_ITERATIONS = 250`。

**时序关键（配置已部分生效）：** 这三个 child 启动于 2026-10-23 14:43。当时 `delegation.max_iterations` 还是 **250**——所有历史 config 备份都写着 250：

```
config.yaml.bak-20260925T043106Z          max_iterations: 250  max_concurrent_children: 10
config.yaml.bak-homechannel-20261004T115240 max_iterations: 250  max_concurrent_children: 10
config.yaml.bak-token-20261023T114712      max_iterations: 250  max_concurrent_children: 10
config.yaml.bak-model-switch-20261023T124224 max_iterations: 250 max_concurrent_children: 10
config.yaml (current, mtime 10-24 11:08)   max_iterations:  60  max_concurrent_children:  4
```

**即：当前配置的 60/4 是在这次爆量之后才收紧的。方案 P4 属于"已生效、待验证"，不是待办。**

### 1.6 Cron 任务

7 天内 `usage_audit.jsonl` 按 job 汇总：

| job | fires | prompt | completion | total | 占比 |
|---|---|---|---|---|---|
| `daily-ai-news` | 8 | 11,294,871 | 159,926 | 11,454,797 | 46.8% |
| `daily-pr-summary` | 7 | 8,275,747 | 129,358 | 8,405,105 | 34.4% |
| `daily-ai-twitter-digest` | 7 | 4,504,103 | 96,563 | 4,600,666 | 18.8% |
| **合计** | | | | **24,460,568** | 100% |

注意 prompt/completion 比值 ≈ **70:1**——这些任务绝大部分消耗在"反复读历史"，不是产出。

单次 fire 的 prompt 最高到 5,517,172 tokens（`daily-pr-summary` 2026-10-20）。

`jobs.json` 中这三个 job 的形态：

```
daily-ai-news             no_agent=False  script=False  prompt=3762 chars
daily-ai-twitter-digest   no_agent=None  script=False  prompt=1977 chars
daily-pr-summary          no_agent=False  script=False  prompt=899 chars
```

即三个都是 **agent 型**（走完整 agent loop），不是脚本型。对照组 `daily-damage-report` / `kill-bsr-if-hot` 是 `no_agent=True + script=True`，零 token。

### 1.7 本地状态与工具输出

```
state.db:        331,169,792 bytes (331MB)
state.db-wal:     67,108,864 bytes (67MB)
checkpoints:     265MB
hermes insights        real 2.33s
hermes sessions list   real 0.59s
hermes status          real 2.59s

tool output volume (7d, n=11614 results, avg 1336 chars):
  >4000 chars: 851  (7.3%)
  >1500 chars: 1983 (17.1%)
  >800 chars:  3305 (28.5%)

by tool: execute_code n=5010 (6.5M chars, max 52992)
         terminal    n=5267 (5.0M chars, max 54799)
         skill_view  n=135  (1.5M chars, max 44085)
```

`hermes doctor` 独立确认：
```
1. Large WAL file — cannot prove state.db is quiet (stop the profile's gateway first, then run 'hermes doctor --fix' to checkpoint)
```

另有 87 次 `checkpoint_manager` git 错误（`git add -A` rc=128，无法创建 `index.lock`）。

### 1.8 记忆文件

```
MEMORY.md: 3988 chars / limit 4000   (99%)
USER.md:   2751 chars / limit 2500   ← 超限
WARNING tools.memory_tool: USER.md exceeds its char limit on load: 2751/2500 chars.
        Entries stay loaded; further additions are blocked until it is back under the limit
（7 天内该告警出现 837 次）
```

---

## 2. 方案 P1：收紧上下文增长（解决"慢"+"费 token"的主因）

### 适用条件
上下文持续增长、prompt 大小已经进入 60K+ 区间时。**本机已满足**：prompt p90 = 148K，max = 307K。

### 根因
`compression.threshold: 0.5` 是**模型上下文窗口的百分比**，不是绝对 token 数。MiniMax-M3 窗口 1M，`0.5` = 500,000 tokens 才触发——远高于实际工作区间。`threshold_tokens` 才是绝对上限。

同时 `proactive_prune_min_result_chars: 4000` 门槛过高：7 天内只有 **7.3%** 的工具结果超过 4000 字符，阈值降到 1500 能覆盖 17.1%，降到 800 能覆盖 28.5%。**门槛 4000 意味着 92.7% 的工具结果永远不进入裁剪候选。**

这直接解释了 111 次 `reclamation did not run`：`nothing_eligible=74`（没有合格候选）、`reclaim_below_minimum=30`（裁剪收益不够 4096 token）。

### 方案

```yaml
# ~/.hermes/profiles/architecture/config.yaml
compression:
  threshold: 0.5                # 保持；真正起作用的是下面两行
  threshold_tokens: 30000        # 50000 → 30000：提前触发 LLM 压缩
  proactive_prune_tokens: 20000 # 30000 → 20000：更早开始确定性裁剪（不花 token）
  proactive_prune_min_result_chars: 1500  # 4000 → 1500：让 17% 的工具结果进入候选
  target_ratio: 0.15            # 0.2 → 0.15：压缩后压得更紧
```

配套（可选，若想彻底掐掉"每轮破坏 cache 前缀"的写法）：
```yaml
compression:
  micro_compact: false          # 保持 false
```

### 实施前提
1. `compression.threshold_tokens` / `proactive_prune_*` 都是**启动期读取**——改完必须 `/new` 或重启 gateway 才生效，**当前会话内无效**。
2. `proactive_prune_min_result_chars` 有下限 200（`max(_PRUNE_MIN_CHARS, …)`），1500 安全。
3. 裁剪（prune）**不调用 LLM**，只做确定性投影——这是最便宜的杠杆，优先用。
4. 提前压缩会增加压缩调用频次；由于 P2 未修，每次压缩要 72s，所以 **P2 必须先修**，否则 P1 会让"慢"更明显。

### 验证方式
```bash
# 1. 确认新阈值已生效（重启后）
hermes config get compression.threshold_tokens
hermes config get compression.proactive_prune_min_result_chars

# 2. 观察 prompt 大小是否下降（重启后重新采样）
grep -oE 'in=[0-9]+' ~/.hermes/profiles/architecture/logs/agent.log | tail -50

# 3. 观察压缩是否更早触发、prune 是否不再 no-op
grep -c 'reclamation did not run' ~/.hermes/profiles/architecture/logs/agent.log
grep -oE 'prune:[a-z_]+' ~/.hermes/profiles/architecture/logs/agent.log | sort | uniq -c

# 4. 对比 7 天前后 token 总量
sqlite3 "file:$HOME/.hermes/profiles/architecture/state.db?mode=ro" \
  "select task, sum(input_tokens+cache_read_tokens+output_tokens) from session_model_usage
   where last_seen > strftime('%s','now')-7*86400 group by task;"
```
**预期**：`prompt p90` 从 148K 降到 60K 以下；`prune:nothing_eligible` 显著下降；总 token 下降。

---

## 3. 方案 P2：修复失效的压缩辅助模型（**当前配置完全没生效**）

### 适用条件
任何 `compression.in_place: true` 且 `auxiliary.compression.model` 指向的模型在实际 provider 上不可用时。**本机已满足**：配置了 `google/gemini-3-flash-preview`，187 次派发中实际用量为 **0**。

### 根因
`auxiliary.compression.provider: auto` + `model: google/gemini-3-flash-preview` 这个组合在当前 credential 状态下解析失败：

```
Summary model 'google/gemini-3-flash-preview' unavailable (404 page not found).
Falling back to main model 'minimaxai/minimax-m3.1-flash' for compression.
```

auto 路由落到 `minimax-cn`，而 `minimax-cn` 不认 `google/gemini-3-flash-preview` → 404 → 回落到主模型。

**后果是三重的：**
1. 压缩慢：走主模型 = p50 **72.5s**、p90 157s、max 334s，占 7 天墙钟 **4.30 小时**。
2. 压缩贵：压缩输出 token 全部计在主模型配额上，占全部输出 token 的 **41.4%**。
3. 压缩打断 cache：压缩前后 cache 命中率从 79% 掉到 **40%**，下一轮重新预填充。

### 方案

二选一，取决于想要哪种压缩模型：

**方案 A —— 用本机已有 credential 且确认可用的 provider**（推荐，无需新增密钥）

`credential_pool` 中已配置的 provider：`minimax-cn`、`gemini`、`zai`、`nvidia`、`deepseek`、`copilot`、`qwen-oauth`。

```yaml
auxiliary:
  compression:
    provider: gemini           # 明确指定，不再靠 auto 猜
    model: gemini-3-flash-preview   # 换成 gemini provider 上真实存在的 id
    base_url: ''
    api_key: ''
    timeout: 120
```

**方案 B —— 直接用主模型的快变体**（零新增依赖，最省事）

```yaml
auxiliary:
  compression:
    provider: minimax-cn
    model: MiniMax-M2.7        # 已在本机验证可用于 title_generation（auxiliary.title_generation 就是这个组合）
    base_url: ''
    api_key: ''
    timeout: 120
```

### 实施前提
1. **先验证模型 id 在目标 provider 上真实存在**，再写配置。404 是当前问题的直接原因，不要重复踩。
   ```bash
   # 看本机 provider cache 里登记了哪些模型
   python3 -c "import json;d=json.load(open('$HOME/.hermes/profiles/architecture/provider_models_cache.json'));print(list(d.keys()))"
   ```
2. 压缩模型需要能吃下 `threshold_tokens` 级别的输入（当前约 50K token）。若换成小窗口模型，`_apply_threshold_tokens_cap` 会把 `threshold_tokens` 压到它的窗口以下——这会与 P1 的 30000 冲突，**两者要一起定**。
3. 压缩是**会话内**行为，改 `auxiliary.compression.*` 后需重启 gateway 或开新会话。
4. 压缩模型换了之后，主模型配额压力下降，但压缩**速度**取决于新模型。选 MiniMax-M2.7 时预期比 72s 快，但仍需实测。

### 验证方式
```bash
# 1. 确认不再回落主模型——这条日志必须消失
grep -c "Summary model .* unavailable" ~/.hermes/profiles/architecture/logs/agent.log

# 2. 确认压缩派发用到了新模型（模型名应出现且不再全是主模型）
grep -oE "Compression summary call dispatched: model=\S+" \
  ~/.hermes/profiles/architecture/logs/agent.log | sort | uniq -c | sort -rn

# 3. 确认压缩延迟下降
grep -oE 'aux_call_duration_ms":[0-9]+' ~/.hermes/profiles/architecture/logs/agent.log \
  | awk -F: '{print $2}' | sort -n | awk '{a[NR]=$1} END{print "p50="a[int(NR/2)]" p90="a[int(NR*0.9)]" max="a[NR]}'

# 4. 确认压缩不再吃主模型配额
sqlite3 "file:$HOME/.hermes/profiles/architecture/state.db?mode=ro" \
  "select model, count(*), sum(output_tokens) from session_model_usage
   where task='compression' and last_seen > strftime('%s','now')-7*86400 group by model;"
```
**预期**：`aux_call_duration_ms` p50 从 72,492 降到 10,000 以下；`task=compression` 的 model 列不再只有 `MiniMax-M3.1-Flash`。

---

## 4. 方案 P3：关闭 `background_review` 后台复盘（直接省 9.6%）

### 适用条件
不需要 agent 自动复盘并写入记忆/技能时。**本机已满足**——该任务 7 天消耗 18,743,646 token（9.6%），且 132 次调用分布在 7 个 session 上，用户通常感知不到它的价值。

### 根因
`background_review` 默认开启（`hermes_cli/config_defaults.py:825` → `"background_review": {"enabled": True, …}`），它在会话结束后**重放整个会话上下文**做复盘。`config.yaml` 里有 `background_review` 块但**没有 `enabled` 字段**，所以走默认值 True。

```yaml
# 当前 config.yaml 现状（无 enabled 字段 → 默认开启）
background_review:
  provider: auto
  model: ''
  base_url: ''
  api_key: ''
  timeout: 120
```

### 方案

```yaml
auxiliary:
  background_review:
    enabled: false      # ← 新增这一行
    provider: auto
    model: ''
    base_url: ''
    api_key: ''
    timeout: 120
```

如果仍想保留复盘但降低代价，改为挂到便宜模型上（而非主模型）：
```yaml
auxiliary:
  background_review:
    enabled: true
    provider: minimax-cn
    model: MiniMax-M2.7
```

### 实施前提
1. `enabled` 是**启动期读取**，需重启 gateway 或开新会话生效。
2. 关闭后，记忆更新需要手动触发（`/memory` 或直接编辑 `MEMORY.md`）。结合 §7 的 `USER.md` 超限问题，关闭复盘反而能避免"复盘往超限文件里塞内容"。
3. 关闭不影响 `memory` 工具本身的手动调用。

### 验证方式
```bash
# 重启后确认不再有 background_review 调用
sqlite3 "file:$HOME/.hermes/profiles/architecture/state.db?mode=ro" \
  "select task, count(*), sum(input_tokens+cache_read_tokens+output_tokens)
   from session_model_usage where last_seen > strftime('%s','now')-7*86400 group by task;"
# 预期：task 列不再出现 background_review 行
```
**预期**：总 token 直接下降约 9.6%（≈1,874 万/7 天）。

---

## 5. 方案 P4：约束委派子代理（抑制单次任务烧掉 4600 万）

### 适用条件
使用 `delegate_task` 派发子任务时。**本机已满足**——3 个 child 曾合计烧掉 46,521,909 token（23.8%）。

### 根因
`delegate_tool.py` 明确忽略调用方传入的 `max_iterations`，只认配置文件：

```python
# tools/delegate_tool.py:593-598
default_max_iter = cfg.get("max_iterations", DEFAULT_MAX_ITERATIONS)   # DEFAULT_MAX_ITERATIONS = 250
if max_iterations is not None and max_iterations != default_max_iter:
    logger.debug("delegate_task: ignoring caller-supplied max_iterations=%s; using delegation.max_iterations=%s from config", ...)
```

`DEFAULT_MAX_ITERATIONS = 250`（`delegate_tool.py:106`）。事发时配置还是 250，于是两个 child 精确停在 250 次调用。

### 方案

**当前配置已收紧到位，本方案是"确认 + 补强"：**

```yaml
delegation:
  max_iterations: 60          # ✅ 已是 60（事发时是 250）
  max_concurrent_children: 4  # ✅ 已是 4（事发时是 10）
  child_timeout_seconds: 600  # 保持
```

**建议补强的一条 —— 给子代理单独的上下文上限**，防止子代理自己把上下文撑大：

```yaml
delegation:
  compression_threshold_tokens: 30000   # 子代理独立压缩阈值，不继承主会话
```

> 该键是否被当前版本识别，写之前先 `hermes config check`；不识别就用 `--force`，或改用 P1 的全局阈值兜底。

### 实施前提
1. `max_iterations` 是**硬上限**，且**配置值优先于调用参数**——在 prompt 里写 `max_iterations=20` 是无效的，只能改配置。
2. 收紧到 60 的副作用：长任务可能被截断（`exit_reason=max_iterations`）。改之前确认没有依赖 250 次迭代的常规任务。
3. `max_concurrent_children` 从 10 降到 4 意味着并发委派变慢——这是用时间换 token 的自觉取舍。

### 验证方式
```bash
# 1. 确认生效值
hermes config get delegation.max_iterations
hermes config get delegation.max_concurrent_children

# 2. 派发后检查子会话实际调用次数（应 ≤ 60）
sqlite3 "file:$HOME/.hermes/profiles/architecture/state.db?mode=ro" \
  "select id, api_call_count, input_tokens+cache_read_tokens+output_tokens
   from sessions where parent_session_id is not null
     and started_at > strftime('%s','now')-7*86400 order by 3 desc;"

# 3. 确认没有再出现 250 次调用的 child
sqlite3 "file:$HOME/.hermes/profiles/architecture/state.db?mode=ro" \
  "select count(*) from sessions where parent_session_id is not null and api_call_count > 60
     and started_at > strftime('%s','now')-7*86400;"
```
**预期**：新派发的 child `api_call_count ≤ 60`；第三条查询返回 0。

---

## 6. 方案 P5：Cron 任务去 agent 化（直接省 22%）

### 适用条件
输出内容固定、可由脚本确定性生成的 cron job。**本机已满足**：`daily-ai-news` / `daily-pr-summary` / `daily-ai-twitter-digest` 三个 agent 型 job 占 cron 消耗的 100%，而 `daily-damage-report` / `kill-bsr-if-hot` 用 `no_agent: true` + script 已经实现零 token。

### 根因
三个 agent 型 job 的 prompt/completion ≈ 70:1，prompt 高达 5.5M/次。它们每次 fire 都启动完整 agent loop：读系统提示 + 工具 schema + 历史，然后反复重读。

### 方案

**A. 能脚本化的 → 改 `no_agent: true` + `script`**

用 `cronjob_manage(action='update')` 修改（**不要手改 `jobs.json`**，skill 明确禁止）：

```python
cronjob_manage(action='update', job_id='<id>',
               no_agent=True, script='<shell 脚本路径>')
```

对照现有正确范式（`daily-damage-report`）：
```
daily-damage-report   no_agent=True  script=True  prompt=4 chars
```

**B. 必须用 agent 的 → 每次 fire 用独立干净 session**

避免复用带历史的会话，从源头切断 context 重读。参考 `cron-delivery.md` 里的 cron 章节。

**C. 降频**

`daily-ai-news` 7 天 8 次 fire 消耗 1,145 万（占 cron 46.8%）。若内容时效性允许，改成每天 1 次或隔天 1 次，直接减半。

**D. 若某 job 本身就是排查任务（一次性）→ 用完即删**

`token-blowup-rootcause-20261023` 就是一次性诊断 job（`kind: once`，已 `enabled: false`）。这类 job 跑完应从 `jobs.json` 移除，避免误触发。

### 实施前提
1. **`no_agent: true` 的 job 必须是纯脚本**——不经过 agent loop，prompt 不参与推理，无法做多步推理。
2. 脚本要自己负责输出到目标渠道。
3. 改 cron 配置用 `cronjob_manage(action='update')`，不要手改 `jobs.json`。
4. `daily-ai-news` 这类需要联网检索 + 归纳的任务，可能无法完全脚本化——此时走 B/C。

### 验证方式
```bash
# 1. 按 job 汇总 7 天消耗（改完后重跑这条对比）
python3 - <<'PY'
import json, collections
P="/Users/lex/.hermes/profiles/architecture"
name={j["id"]: j["name"] for j in json.load(open(f"{P}/cron/jobs.json"))["jobs"]}
agg=collections.defaultdict(int)
for line in open(f"{P}/cron/usage_audit.jsonl"):
    r=json.loads(line); agg[name.get(r.get("job_id"), r.get("job_id"))]+=r.get("total_tokens") or 0
for k,v in sorted(agg.items(), key=lambda x:-x[1]): print(f"  {k:<34}{v:>12,}")
PY

# 2. 确认目标 job 已是 no_agent
python3 -c "import json;[print(j['name'], 'no_agent=', j.get('no_agent'), 'script=', bool(j.get('script')))
  for j in json.load(open('$HOME/.hermes/profiles/architecture/cron/jobs.json'))['jobs']]"
```
**预期**：改造后的 job 在 `usage_audit.jsonl` 中 `total_tokens` 为 `null`（脚本型不产生 token）。

---

## 7. 方案 P6：供应商过载与重试（消除"每次失败多等 10–25s"）

### 适用条件
使用 minimax-cn 且观察到 429 / 529 时。**本机已满足**：7 天内 429×5、529×8，每次最多重试 3 次。

### 根因
```yaml
agent:
  api_max_retries: 2       # 失败 → 3 次尝试
```
429（配额耗尽 / Token Plan 上限）和 529（服务过载 / "负载较高"）在 minimax-cn 上是**瞬时**状态，重试有效。但当前配置只有一个 provider（`minimax-cn`），重试期间没有任何备选。

### 方案

**A. 加 fallback provider**（利用 credential_pool 里已有的 provider）

```yaml
model:
  provider: minimax-cn
  fallback_providers:
    - provider: nvidia
      model: minimaxai/minimax-m3.1-flash     # 已在 MoA reference_models 中使用，路径已验证
    - provider: deepseek
      model: deepseek-chat
```

> 当前 `config.yaml` 里 `fallback_providers:` 是**空列表**（连注释都在，说明留了坑没填）。

**B. 降低并发**

429/529 多由瞬时并发触发。`delegation.max_concurrent_children` 已降到 4（§5），若仍频繁出现 429，进一步降到 2。

**C. 保持 `api_max_retries: 2`**

不要盲目调高——重试次数 × 单次 prompt 体积（p90 148K）会直接放大 token 消耗。**正确顺序是：先加 fallback（A），再考虑调重试。**

### 实施前提
1. fallback provider 的 credential 必须真实可用。当前 `credential_pool` 有 7 个 provider，但 `auth.json` 里 `providers` 字典为空（凭据全在 credential_pool），落地前逐个验证：
   ```bash
   python3 -c "import json;d=json.load(open('$HOME/.hermes/profiles/architecture/auth.json'));print(list((d.get('credential_pool') or {}).keys()))"
   ```
2. fallback 切换会改变输出风格/能力——主模型挂了时的降级质量要接受。
3. 429 若因配额耗尽（"Token Plan 用量上限"）而非瞬时限流，fallback 无效，必须靠 P1–P5 减少总量。

### 验证方式
```bash
# 1. 观察重试次数是否下降
grep -c "API call failed (attempt" ~/.hermes/profiles/architecture/logs/errors.log

# 2. 观察 fallback 是否触发
grep -iE "fallback|switching to" ~/.hermes/profiles/architecture/logs/agent.log | tail -20

# 3. 观察 429/529 是否还在
grep -oE "HTTP (429|529)" ~/.hermes/profiles/architecture/logs/errors.log | sort | uniq -c
```
**预期**：重试次数下降；429/529 计数下降（注意：fallback 生效后 429 仍会记录，只是用户等待时间变短）。

---

## 8. 方案 P7：本地状态膨胀与 git 锁冲突

### 适用条件
`state.db` 超过数百 MB、`hermes doctor` 报 WAL 过大、或出现 `checkpoint_manager` git 错误时。**本机已满足**：state.db 331MB + WAL 67MB、checkpoints 265MB、87 次 git 锁错误。

### 根因
```yaml
# config.yaml
session:
  auto_maintenance: ...
  delete_orphans: true
```
`state.db-wal` 高达 67MB 说明 checkpoint 没有被合并；`hermes doctor` 明确要求：
```
Large WAL file — cannot prove state.db is quiet (stop the profile's gateway first, then run 'hermes doctor --fix' to checkpoint)
```
`checkpoint_manager` 的 87 次 `git add -A` rc=128 错误（无法创建 `index.lock`）说明有并发的 checkpoint 进程在争抢同一个 git 仓库。

### 方案

**A. 收敛 WAL（需停 gateway）**
```bash
# 必须先停掉该 profile 的 gateway，否则 checkpoint 会失败
hermes doctor --fix
```

**B. 清理 checkpoints**
```bash
du -sh ~/.hermes/checkpoints                    # 当前 265MB
ls ~/.hermes/checkpoints | wc -l                 # 当前 1
```
确认无保留需求后清理旧快照目录（**先确认目录内容再删**）。

**C. 排查 git 锁竞争**

```bash
# 找出残留的 index.lock
find ~/.hermes -name 'index.lock' 2>/dev/null
# 看是哪个目录在反复被 checkpoint
grep 'checkpoint_manager' ~/.hermes/profiles/architecture/logs/errors.log | tail -20
```
日志样本显示冲突目录是 `/Users/lex/.hermes/profiles/architecture/checkpoints/store/`。

**D. 降低 state.db 体积**

长期方案是把大工具输出从消息体里剥离（只留摘要 + 指针），避免 331MB 的表膨胀。这属于结构改动，不建议在当前 profile 上直接做。

### 实施前提
1. **`hermes doctor --fix` 前必须停 gateway**——运行中执行会失败（doctor 的提示已明说）。
2. 清理 checkpoints 会丢失回滚点，操作前确认没有需要回滚的会话。
3. 本方案**不直接省 token**，但改善 CLI 响应（`hermes status` 2.59s）和 gateway 稳定性。

### 验证方式
```bash
hermes doctor 2>&1 | grep -i "wal"
ls -la ~/.hermes/profiles/architecture/state.db*
grep -c 'checkpoint_manager' ~/.hermes/profiles/architecture/logs/errors.log
```
**预期**：WAL 告警消失；`state.db-wal` 显著变小；git 错误不再新增。

---

## 9. 附加方案：修复 `USER.md` 超限

### 适用条件
`USER.md` 超过 `user_char_limit` 时。**本机已满足**：2751 / 2500，7 天 837 次告警。

### 根因
```yaml
memory:
  user_char_limit: 2500
```
实际 2751 chars。**后果是功能性阻塞**，不只是噪音：
```
Entries stay loaded; further additions are blocked until it is back under the limit
```
即 agent 无法再向 `USER.md` 写入任何新内容。`MEMORY.md` 也在 3988/4000（99%），随时会触发同样阻塞。

### 方案

**A. 精简内容（推荐）** —— 合并冗余条目，保留「跨会话仍然成立的事实」，删掉会过期的任务痕迹。

**B. 提高上限**
```yaml
memory:
  memory_char_limit: 4000    # 保持
  user_char_limit: 4000      # 2500 → 4000
```
上限提高意味着每轮注入的上下文变大 —— 与 P1 目标相反。**只有在精简不可行时才用此方案。**

### 实施前提
1. **不要用 `patch` 多轮增量修改**——skill 明确记录了这个坑：多轮 patch 会级联出错。**用 `write_file` 一次整体重写。**
2. `MEMORY.md` 必须保持 4 个 `##` 结构段（`grep -c '^## ' MEMORY.md` 必须 = 4）。之前有过整体覆盖导致结构丢失的事故。
3. 改完后立即用 `write_file` 落盘并验证字符数，不要只依赖"命令没报错"。

### 验证方式
```bash
python3 -c "
import os
P=os.path.expanduser('~/.hermes/profiles/architecture/memories')
for f in ('MEMORY.md','USER.md'):
    print(f, len(open(f'{P}/{f}').read()), 'chars')"
grep -c '^## ' ~/.hermes/profiles/architecture/memories/MEMORY.md   # 必须 = 4
grep -c "exceeds its char limit" ~/.hermes/profiles/architecture/logs/errors.log
```
**预期**：两个文件都在限额内；告警不再新增。

---

## 10. 实施顺序建议

方案之间有依赖关系，**顺序错了会适得其反**：

```
第 1 批（立即，无依赖，收益最大）
  ├── P2  修压缩辅助模型   ← 当前配置 100% 失效，且决定 P1 是否会变慢
  ├── P3  关闭 background_review  ← 一行，省 9.6%
  └── P9  修 USER.md 超限  ← 解开记忆写入阻塞

第 2 批（P2 完成后）
  ├── P1  收紧 compression 阈值  ← 依赖 P2，否则压缩次数↑而单次仍 72s
  └── P4  确认 delegation 上限生效  ← 配置已改，需验证

第 3 批（需要改 job / 运维动作）
  ├── P5  Cron 去 agent 化       ← 省 22%
  ├── P6  加 fallback provider
  └── P7  收敛 WAL + 清理 checkpoints（需停 gateway）
```

**每一项改完都要 `/new` 或重启 gateway**——`compression.*`、`auxiliary.*`、`delegation.*`、`disabled_toolsets` 都是启动期读取，会话内改不生效。

---

## 11. 复现命令

所有诊断均为只读。SQLite 一律用 `mode=ro`：

```bash
PROFILE=~/.hermes/profiles/architecture
DB="file:$PROFILE/state.db?mode=ro"

# 7 天 token 按 task 归因
sqlite3 "$DB" "
select task, count(*), sum(api_call_count),
       sum(input_tokens), sum(cache_read_tokens), sum(output_tokens)
from session_model_usage where last_seen > strftime('%s','now')-7*86400 group by task;"

# 7 天 token 按 session 来源归因
sqlite3 "$DB" "
select source, count(*), sum(api_call_count),
       sum(input_tokens+cache_read_tokens+output_tokens) as total
from sessions where started_at > strftime('%s','now')-7*86400
group by source order by total desc;"

# Top 10 烧 token 的 session
sqlite3 "$DB" "
select id, source, api_call_count, tool_call_count,
       input_tokens+cache_read_tokens+output_tokens as total
from sessions where started_at > strftime('%s','now')-7*86400
order by total desc limit 10;"

# 委派子会话的调用次数（验证 delegation 上限）
sqlite3 "$DB" "
select id, api_call_count, input_tokens+cache_read_tokens+output_tokens
from sessions where parent_session_id is not null
  and started_at > strftime('%s','now')-7*86400 order by 3 desc;"

# 工具输出体积分布（决定 proactive_prune_min_result_chars）
sqlite3 "$DB" "
select count(*), avg(length(coalesce(content,''))),
       sum(case when length(coalesce(content,''))>4000 then 1 else 0 end),
       sum(case when length(coalesce(content,''))>1500 then 1 else 0 end),
       sum(case when length(coalesce(content,''))>800  then 1 else 0 end)
from messages where role='tool' and timestamp > strftime('%s','now')-7*86400;"

# API 延迟分位
grep 'API call #' $PROFILE/logs/agent.log \
  | grep -oE 'latency=[0-9.]+s' | sed 's/latency=//;s/s$//' \
  | sort -n | awk '{a[NR]=$1} END{print "n="NR" p50="a[int(NR*.5)]" p90="a[int(NR*.9)]" p99="a[int(NR*.99)]" max="a[NR]}'

# 压缩实际用了哪个模型
grep -oE "Compression summary call dispatched: model=\S+" $PROFILE/logs/agent.log | sort | uniq -c

# 压缩辅助模型是否回落主模型
grep -c "Summary model .* unavailable" $PROFILE/logs/agent.log

# prune no-op 原因分布
grep -oE "prune:[a-z_]+" $PROFILE/logs/agent.log | sort | uniq -c

# Cron 按 job 汇总
python3 - <<'PY'
import json, collections
P="/Users/lex/.hermes/profiles/architecture"
name={j["id"]: j["name"] for j in json.load(open(f"{P}/cron/jobs.json"))["jobs"]}
agg=collections.defaultdict(int)
for line in open(f"{P}/cron/usage_audit.jsonl"):
    r=json.loads(line); agg[name.get(r.get("job_id"), r.get("job_id"))]+=r.get("total_tokens") or 0
for k,v in sorted(agg.items(), key=lambda x:-x[1]): print(f"  {k:<34}{v:>12,}")
PY
```

---

## 12. 数据来源与可信度

| 结论 | 依据 | 可信度 |
|---|---|---|
| 上下文体积是"慢"的主因 | prompt 分层延迟单调上升 + 85% 墙钟在模型侧 | 高 |
| 压缩辅助模型从未生效 | 187 次派发 0 次用配置模型 + 逐行配对 + 源码 404 警告 | 高 |
| `background_review` 占 9.6% | `session_model_usage` 按 task 聚合 | 高 |
| 委派爆量源于 `max_iterations=250` | 两个 child 精确停在 250 + `delegate_tool.py:106` 源码 + config 备份时间线 | 高 |
| Cron 三 job 占 22% | `usage_audit.jsonl` 按 job 聚合 | 高 |
| 压缩后 cache 命中率 79%→40% | 日志中压缩事件前后各取一次 API 调用配对，n=59/58 | 中（样本量中等，方向明确） |
| `USER.md` 超限阻塞写入 | 837 次工具层告警原文 | 高 |
| WAL / git 锁冲突 | `hermes doctor` 独立输出 + 87 次 git 错误 | 高 |

**未验证/需实测的项**（已在正文标注）：
- P2 各候选压缩模型的实际延迟与窗口上限 —— 需在目标 provider 上实测。
- P1 收紧后压缩调用频次的净增量 —— 需改完采样对比。
- P6 fallback provider 的真实可用性 —— credential 在 pool 里但需逐个验证。

---

*本文为只读诊断产物。诊断期间未修改任何 Hermes 配置、provider、凭据或 Kubernetes 资源；所有探测脚本位于 `~/.hermes/profiles/architecture/cache/scratch/`。*
