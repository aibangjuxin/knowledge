# ob/ —— SMS Secret Manager Onboarding POC

用 **配置文件驱动** 的方式，演示 Secret Manager 的 API Onboarding 与 Secret 创建两个流程。

> 这是一个 **POC**：重点是「**怎么跑**」和「**入参怎么从 config 传进来**」，
> 而不是代码的工程化程度。所有 API 调用都是模拟打印。

---

## 1. 目录结构

```
ob/
├── common.py                  # 公共库：配置加载 / 参数解析 / 日志 / SM 客户端封装
├── secret_api_onboarding.py   # 脚本 1：API 级 onboarding（建 RT GSA + 空 secret + IAM）
├── secret_api_create.py       # 脚本 2：创建/写入 secret（建 secret + 写 version + 绑 accessor）
├── ob.example.json            # 脚本 1 的配置示例
├── secret.create.json         # 脚本 2 的配置示例
├── requirements.txt           # 依赖说明（零依赖也能跑）
└── README.md
```

---

## 2. 怎么跑

### 2.1 最小可跑命令

```bash
cd /Users/lex/git/knowledge/gcp/secret-manage/ob

# 脚本 1：Onboarding
python3 secret_api_onboarding.py --config ob.example.json

# 脚本 2：创建 secret
python3 secret_api_create.py --config secret.create.json
```

**不需要 pip install 任何东西**——没装 GCP SDK 时会自动降级成「模拟模式」，
把所有将要执行的 API 调用打印出来。

### 2.2 常用参数

两个脚本**共用**一套参数（定义在 `common.base_parser()`）：

| 参数 | 作用 |
|---|---|
| `--config <file>` | **必填**，配置文件路径（JSON） |
| `--project <id>` | 覆盖配置里的 project id |
| `--dry-run` | 只打印动作，不调 API |
| `-v / --verbose` | 打印 DEBUG 日志 |
| `--env <env>` | 覆盖配置里的 `targetEnv` |
| `--payload-from-file <file>` | （仅 create 脚本）从 `key=value` 文件读真实 payload |

### 2.3 典型用法

```bash
# 1) 先 dry-run 看流程
python3 secret_api_onboarding.py --config ob.example.json --dry-run -v

# 2) onboarding，指定 project
python3 secret_api_onboarding.py --config ob.example.json --project my-proj

# 3) 用真实 payload 创建 secret
cat > /tmp/payload.txt <<'EOF'
agent-almjiratoken=REAL_TOKEN_ABC
agent-dspusername=real_user
EOF
python3 secret_api_create.py --config secret.create.json \
  --payload-from-file /tmp/payload.txt

# 4) 换环境
python3 secret_api_create.py --config secret.create.json --env prod
```

---

## 3. 配置字段说明

### 3.1 `ob.example.json`（onboarding 用）

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `targetEnv` | string | ✅ | 目标环境（dev / uat / prod） |
| `region` | string | ✅ | 区域（uk 等） |
| `teamName` | string | ✅ | 团队名，用于推导 secret id / group 名 |
| `apiName` | string | ✅ | API 名 |
| `ticketNum` | string | ✅ | 工单号，会写进 secret labels |
| `keyNameList` | string[] | ✅ | 需要纳入管理的 secret key 列表 |
| `iamEnable` | bool | ❌ | 是否给 RT GSA 绑 IAM 管理员角色 |
| `eimAppId` | string | ❌ | EIM 应用 ID |
| `changeFileName` | string | ❌ | API 元数据 yaml 的相对路径 |
| `updateSecretAccess` | bool | ❌ | 是否刷新已有 accessor |
| `triggerJobTimeout` | int | ❌ | 触发下游任务的超时（秒） |
| `sourceVersion` | int | ❌ | 元数据版本号 |
| `jenkinsProjectName` | string | ❌ | 下游 Jenkins project |

### 3.2 `secret.create.json`（create 用）

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `targetEnv` | string | ✅ | 目标环境 |
| `region` | string | ✅ | 区域 |
| `teamName` | string | ✅ | 团队名 |
| `apiName` | string | ✅ | API 名 |
| `ticketNum` | string | ✅ | 工单号 |
| `secretProjectId` | string | ✅ | secret 所在的 GCP project |
| `projectGcpSa` | string | ❌ | 运行期读取 secret 的 SA（绑 accessor 用） |
| `keyNameList` | string[] | ✅ | 要写入的 key 列表 |
| `updateSecretAccess` | bool | ❌ | 是否刷新已有 accessor |
| `grantGroupAccessor` | bool | ❌ | 是否给 Group 绑 accessor |

### 3.3 字段 → 代码的映射

```
config 字段            脚本                                效果
──────────────────────────────────────────────────────────────────────────
targetEnv/region      两个脚本都读                        拼 secret id / 打标签
teamName              两个脚本都读                        → secret id 前缀 + group 名
apiName               两个脚本都读                        → secret id + RT SA 名
ticketNum             两个脚本都读                        → secret label
keyNameList           两个脚本都读                        → create 时逐个写 version
secretProjectId       create 读（onboarding 没有）        → SM 的 parent project
projectGcpSa          create 读                           → accessor 绑定对象
iamEnable             onboarding 读                       → 是否绑 IAM admin
updateSecretAccess    两个脚本都读                        → 是否刷新 accessor
grantGroupAccessor    create 读                           → 是否给 group 绑 accessor
changeFileName        onboarding 读                       → 元数据 yaml 路径
triggerJobTimeout     onboarding 读                       → 触发下游超时
jenkinsProjectName    onboarding 读                       → 下游任务
eimAppId              onboarding 读                       → EIM 应用
sourceVersion         onboarding 读                       → 元数据版本
```

**secret id 推导规则**（在 `common.build_secret_id()`）：

```python
SECRET_ID_TEMPLATE = "{team}-{api}-{env}"
# team123 + testapi + dev → "team123-testapi-dev"
```

---

## 4. 流程

```
┌──────────────────────────────────────────────────────────────┐
│ secret_api_onboarding.py --config ob.example.json           │
├──────────────────────────────────────────────────────────────┤
│ STEP 1  创建专用 RT GSA        rt-sa-{api}-{env}            │
│ STEP 2  初始化空 payload secret  {team}-{api}-{env}         │
│ STEP 3  分配 IAM 角色           group → admin, GSA → viewer │
│ STEP 4  更新 API 元数据          changeFileName 指向的 yaml  │
│ STEP 5  触发下游 Jenkins 任务    jenkinsProjectName          │
└──────────────────────────────────────────────────────────────┘
                            ↓
┌──────────────────────────────────────────────────────────────┐
│ secret_api_create.py --config secret.create.json             │
├──────────────────────────────────────────────────────────────┤
│ STEP 1  检查 secret 是否存在     不存在则 create_secret      │
│ STEP 2  按 keyNameList 写 version  每个 key 一个 version      │
│ STEP 3  绑定 accessor           SA / Group                  │
│ STEP 4  汇总输出                                        │
└──────────────────────────────────────────────────────────────┘
```

> 这个顺序对应 `../onboarding.md` 里的 "Once per API onboarding" 流程
> （建 RT GSA → 初始化空 secret → 分配角色 → 更新元数据）。

---

## 5. 代码结构：config 是怎么传进来的

这是本 POC 最想说明的部分。

```
命令行
  │  python3 secret_api_create.py --config secret.create.json
  ▼
argparse（common.base_parser）
  │  args.config = "secret.create.json"
  ▼
common.load_config(path)
  │  json.load() → dict
  │  顺手塞一个 _configPath 方便报错定位
  ▼
common.require(cfg, *REQUIRED)        ← 前置校验，缺字段直接退出码 2
  │
  ▼
run_create(cfg, args, log)
  │  cfg["targetEnv"] / cfg["keyNameList"] / ...
  ▼
SecretManagerClient(project, dry_run=args.dry_run)
  │
  ▼
sm.create_secret(...) / sm.add_secret_version(...) / sm.set_iam_policy(...)
```

**要点**：

1. **配置内容不硬编码在脚本里**。脚本只认「字段名」，字段值全来自 JSON。
2. **前置校验**。缺字段在跑第一步之前就报错退出，不会跑到一半才炸。
   退出码约定：`0` 成功、`1` 执行异常、`2` 配置错误、`130` 被中断。
3. **命令行可以覆盖配置**：`--project` > 配置里的 `secretProjectId` > `GOOGLE_CLOUD_PROJECT` 环境变量。
4. **真实/模拟同一套代码路径**。`SecretManagerClient` 内部判断能不能建真实客户端，
   不能就降级成打印。dry-run 强制走打印分支。

### SecretManagerClient 的降级逻辑

```python
SecretManagerClient(project, dry_run=False)
  ├─ dry_run=True          → "dry-run" 模式，全部打印
  ├─ 能 import SDK 且有凭据 → "real" 模式，真调 API
  └─ 否则                  → "simulate" 模式，打印 API 调用
```

```
[17:27:11] WARN  未能初始化真实客户端(ModuleNotFoundError: No module named 'google')，降级为模拟模式
[17:27:11] INFO    → API create_secret(secret_id=team123-testapi-dev, labels={...}, replication=['automatic'])
```

---

## 6. 怎么接真实 GCP API

### 6.1 装依赖

```bash
pip install -r requirements.txt
# 或
pip install google-cloud-secretmanager
```

### 6.2 配认证

三种方式，任选其一：

```bash
# A. Application Default Credentials
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/adc.json

# B. gcloud 本地登录
gcloud auth application-default login

# C. Docker / 跳板机：挂载 gcloud 凭据目录
#    详见 ../../gke/gcloud-auth-login-docker.md
```

### 6.3 验证切到 real 模式

```bash
python3 secret_api_create.py --config secret.create.json --project my-proj
# 期望看到：
#   [INFO] SecretManager 模式: REAL (project=my-proj)
# 而不是：
#   [WARN] 未能初始化真实客户端(...)，降级为模拟模式
```

---

## 7. 还没实现的（POC 边界）

明确一下这个 demo **故意没做**的事，避免误用：

| 没做的 | 真实实现里应该是 |
|---|---|
| payload 用占位字符串 | 从 EIM / KMS / CI 变量取真实密文 |
| IAM 绑定只是打印 | 真的调 `iam.serviceAccounts.setIamPolicy` |
| 建 SA 只是打印 | 真的调 `iam.serviceAccounts.create` |
| yaml 只读不写 | 真的更新 API 元数据 |
| 不触发 Jenkins | 真的调 Jenkins API |
| 没有重试 / 幂等 | secret 已存在应复用而不是重建 |
| payload 明文进日志 | **真实实现里绝对不能打印 payload**（POC 为了演示才打印） |

> ⚠️ **安全问题**：POC 里 `add_secret_version` 会打印 payload 前 32 字节。
> 真实实现**必须去掉**这个日志，否则密钥会进 CI 日志。

---

## 8. 相关文档

- [../onboarding.md](../onboarding.md) — SMS Onboarding 完整流程（含 Mermaid 时序图）
- [../gcp-secret.md](../gcp-secret.md) — Secret Manager 基础
- [../gcp-secret-manage-rotate.md](../gcp-secret-manage-rotate.md) — 密钥轮换
- [../add-sa-to-manager.md](../add-sa-to-manager.md) — SA 授权
- [../../gke/gcloud-auth-login-docker.md](../../gke/gcloud-auth-login-docker.md) — Docker 里跑 gcloud 的凭据方案
