// Package rules 实现 CR Check 的判定引擎。
//
// ★ 设计原则：collect-all（收集式）而不是 fail-fast（快速失败）。
// 需求 R10 要求"check 详情里写明**哪条规则**不通过、缺什么"，
// 快速失败只能告诉用户第一个问题 → 用户改完再提交 → 又撞上第二个 → 体验极差。
package rules

import (
	"context"
	"fmt"
	"strings"
	"sync"
	"time"

	"github.com/acme/cr-check/internal/config"
	"github.com/acme/cr-check/internal/crplatform"
)

// PRInfo 是被判定对象（PR）的快照。
type PRInfo struct {
	Number    int
	Owner     string
	Repo      string
	BaseRef   string
	HeadSHA   string
	Requester string
	Labels    []string
	Body      string
	Title     string
}

// Key 是 PR 的唯一标识（owner/repo#number）。
func (p PRInfo) Key() string {
	return fmt.Sprintf("%s/%s#%d", p.Owner, p.Repo, p.Number)
}

// Input 是判定的全部输入。
type Input struct {
	PR         PRInfo
	CR         *crplatform.ChangeRequest // 可能为 nil（变更单不存在）
	Extraction Extraction
	Now        time.Time
	Policy     *config.Config
}

// Result 是单条规则的判定结果。
type Result struct {
	ID      string `json:"id"`
	Passed  bool   `json:"passed"`
	Message string `json:"message"`
}

// Outcome 是一次判定的完整结论。
type Outcome struct {
	OK            bool      `json:"ok"`
	SystemError   bool      `json:"system_error"`
	SystemMessage string    `json:"system_message,omitempty"`
	CRNumber      string    `json:"cr_number,omitempty"`
	Env           string    `json:"env,omitempty"`
	Results       []Result  `json:"rules"`
	Skipped       []string  `json:"skipped,omitempty"`
	EvaluatedAt   time.Time `json:"evaluated_at"`
}

// Conclusion 返回 check run 的结论。
//
// ★ 铁律：只能出现 success / failure / action_required。
// GitHub 把 skipped / neutral **当作通过** → 写了等于开门。
func (o Outcome) Conclusion() string {
	if o.OK && !o.SystemError {
		return "success"
	}
	return "failure"
}

// FailedIDs 返回失败的规则 ID。
func (o Outcome) FailedIDs() []string {
	var out []string
	for _, r := range o.Results {
		if !r.Passed {
			out = append(out, r.ID)
		}
	}
	return out
}

// Render 把结论渲染成 check run 的 Markdown 输出。
func (o Outcome) Render() string {
	var b strings.Builder

	if o.SystemError {
		b.WriteString("### ⚠️ 门禁系统异常，本次判定未完成\n\n")
		b.WriteString("**这不是你的 PR 有问题**，是门禁服务没能完成判定。\n\n")
		fmt.Fprintf(&b, "错误：`%s`\n\n", o.SystemMessage)
		b.WriteString("已触发告警。系统恢复后会自动重评；急需放行请联系平台组走人工审批。\n")
		return b.String()
	}

	if o.OK {
		b.WriteString("### ✅ 变更单校验通过\n\n")
	} else {
		b.WriteString("### ❌ 变更单校验未通过\n\n")
	}
	if o.CRNumber != "" {
		fmt.Fprintf(&b, "- **变更单**：`%s`\n", o.CRNumber)
	}
	if o.Env != "" {
		fmt.Fprintf(&b, "- **目标环境**：`%s`\n", o.Env)
	}
	fmt.Fprintf(&b, "- **判定时刻**：`%s`\n", o.EvaluatedAt.Format(time.RFC3339))
	b.WriteString("\n")

	b.WriteString("| 规则 | 结果 | 说明 |\n|---|---|---|\n")
	for _, r := range o.Results {
		mark := "✅"
		if !r.Passed {
			mark = "❌"
		}
		fmt.Fprintf(&b, "| `%s` | %s | %s |\n", r.ID, mark, r.Message)
	}
	if len(o.Skipped) > 0 {
		b.WriteString("\n> 本版本未实现的规则：" + strings.Join(o.Skipped, ", ") + "\n")
	}
	if !o.OK {
		b.WriteString("\n**请修正上述 ❌ 项后重新 push，check 会自动重跑。**\n")
	}
	return b.String()
}

// ─────────────────────────────────────────────────────────────
// Engine
// ─────────────────────────────────────────────────────────────

// Usage 记录"哪个变更单被哪个 PR 占用"（R7 唯一性）。
type Usage struct {
	mu sync.Mutex
	m  map[string]string
}

// NewUsage 构造占用表。
func NewUsage() *Usage { return &Usage{m: map[string]string{}} }

// Claim 尝试为 PR 占用一个变更单。
// 返回 false 表示该变更单已被别的 PR 占用。
func (u *Usage) Claim(crNumber, prKey string) bool {
	u.mu.Lock()
	defer u.mu.Unlock()
	if owner, ok := u.m[crNumber]; ok && owner != prKey {
		return false
	}
	u.m[crNumber] = prKey
	return true
}

// Owner 返回某个变更单当前的占用者。
func (u *Usage) Owner(crNumber string) (string, bool) {
	u.mu.Lock()
	defer u.mu.Unlock()
	o, ok := u.m[crNumber]
	return o, ok
}

// Release 释放占用。
func (u *Usage) Release(crNumber string) {
	u.mu.Lock()
	defer u.mu.Unlock()
	delete(u.m, crNumber)
}

// Engine 是判定引擎。
type Engine struct {
	cfg     *config.Config
	windows map[string]*Window
	usage   *Usage
}

// NewEngine 构造引擎（会解析所有维护窗口）。
func NewEngine(cfg *config.Config) (*Engine, error) {
	e := &Engine{
		cfg:     cfg,
		windows: map[string]*Window{},
		usage:   NewUsage(),
	}
	for _, wc := range cfg.Windows {
		w, err := ParseWindow(wc, cfg.Timezone)
		if err != nil {
			return nil, err
		}
		e.windows[wc.Env] = w
	}
	return e, nil
}

// Usage 暴露占用表（供测试与运维查询）。
func (e *Engine) Usage() *Usage { return e.usage }

// rule 是一条规则的内部表示。
type rule struct {
	id string
	fn func(ctx context.Context, e *Engine, in Input) Result
}

// Evaluate 按顺序执行全部规则，**收集全部结果**。
func (e *Engine) Evaluate(ctx context.Context, in Input) Outcome {
	out := Outcome{
		OK:          true,
		CRNumber:    in.Extraction.First(),
		Env:         e.cfg.EnvForBranch(in.PR.BaseRef),
		EvaluatedAt: in.Now,
	}

	for _, r := range e.rules() {
		res := r.fn(ctx, e, in)
		out.Results = append(out.Results, res)
		if !res.Passed {
			out.OK = false
		}
	}

	// 本版本尚未实现的规则（诚实列出，不假装通过）
	out.Skipped = []string{"R5b 变更内容一致性", "R8 紧急通道 break-glass", "R12 部署侧可追溯"}
	return out
}

// rules 返回规则列表（顺序即执行顺序）。
func (e *Engine) rules() []rule {
	return []rule{
		{"R1", ruleR1},
		{"R1a", ruleR1a},
		{"R2", ruleR2},
		{"R3", ruleR3},
		{"R4", ruleR4},
		{"R5", ruleR5},
		{"R6", ruleR6},
		{"R6w", ruleR6w},
		{"R7", ruleR7},
	}
}

// ── R1：PR 必须携带变更单号 ────────────────────────────────
func ruleR1(_ context.Context, _ *Engine, in Input) Result {
	if len(in.Extraction.Numbers) == 0 {
		return Result{"R1", false, fmt.Sprintf(
			"PR 未携带变更单号（需要 label `%s<编号>`，或 body 里写 `%s <编号>`）",
			in.Policy.CR.LabelPrefix, in.Policy.CR.BodyMarker)}
	}
	return Result{"R1", true, fmt.Sprintf("解析到变更单号：%s", in.Extraction.Describe())}
}

// ── R1a：必须且只能有一个变更单号 ──────────────────────────
func ruleR1a(_ context.Context, _ *Engine, in Input) Result {
	switch {
	case len(in.Extraction.Numbers) == 0:
		return Result{"R1a", false, "没有解析到任何变更单号"}
	case len(in.Extraction.Numbers) == 1:
		return Result{"R1a", true, "变更单号唯一"}
	default:
		if in.Extraction.Conflict {
			return Result{"R1a", false, fmt.Sprintf(
				"不同载体给出了**不同**的变更单号 %v（%s）—— 这是冲突，必须先修正",
				in.Extraction.Numbers, in.Extraction.Describe())}
		}
		return Result{"R1a", false, fmt.Sprintf(
			"解析出多个变更单号 %v，一个 PR 必须且只能关联一个变更单", in.Extraction.Numbers)}
	}
}

// ── R2：变更单存在 ───────────────────────────────────────
func ruleR2(_ context.Context, _ *Engine, in Input) Result {
	if in.CR == nil {
		return Result{"R2", false, fmt.Sprintf("变更单 %s 在 CR 管理平台上不存在", in.Extraction.First())}
	}
	return Result{"R2", true, fmt.Sprintf("变更单 %s 存在", in.CR.Number)}
}

// ── R3：变更单状态可执行 ──────────────────────────────────
func ruleR3(_ context.Context, e *Engine, in Input) Result {
	if in.CR == nil {
		return Result{"R3", false, "变更单不存在，无法判断状态"}
	}
	if !e.cfg.IsExecutableStatus(string(in.CR.Status)) {
		return Result{"R3", false, fmt.Sprintf(
			"变更单 %s 当前状态为 `%s`，需要 %s",
			in.CR.Number, in.CR.Status, strings.Join(e.cfg.CR.AllowedExecutableStatuses, " / "))}
	}
	return Result{"R3", true, fmt.Sprintf("变更单 %s 状态为 `%s`（可执行）", in.CR.Number, in.CR.Status)}
}

// ── R4：审批充分 ──────────────────────────────────────────
func ruleR4(_ context.Context, e *Engine, in Input) Result {
	if in.CR == nil {
		return Result{"R4", false, "变更单不存在，无法检查审批"}
	}
	approvers := in.CR.ApproverNames()
	if len(approvers) < e.cfg.CR.MinApprovals {
		return Result{"R4", false, fmt.Sprintf(
			"变更单 %s 的审批人只有 %d 位（%s），需要至少 %d 位",
			in.CR.Number, len(approvers), strings.Join(approvers, ", "), e.cfg.CR.MinApprovals)}
	}
	if e.cfg.CR.ForbidSelfApproval && containsFold(approvers, in.PR.Requester) {
		return Result{"R4", false, fmt.Sprintf("提单人 %s 不能审批自己的变更单", in.PR.Requester)}
	}
	if len(e.cfg.CR.AllowedApprovers) > 0 {
		for _, a := range approvers {
			if !containsFold(e.cfg.CR.AllowedApprovers, a) {
				return Result{"R4", false, fmt.Sprintf("审批人 %s 不在授权名单内（%s）",
					a, strings.Join(e.cfg.CR.AllowedApprovers, ", "))}
			}
		}
	}
	return Result{"R4", true, fmt.Sprintf("审批充分：%s", strings.Join(approvers, ", "))}
}

// ── R5：目标环境与分支一致 ────────────────────────────────
func ruleR5(_ context.Context, e *Engine, in Input) Result {
	if in.CR == nil {
		return Result{"R5", false, "变更单不存在，无法比对目标环境"}
	}
	want := e.cfg.EnvForBranch(in.PR.BaseRef)
	if want == "" {
		return Result{"R5", false, fmt.Sprintf(
			"分支 `%s` 没有配置环境映射（branchEnvMap），无法判定目标环境", in.PR.BaseRef)}
	}
	if !strings.EqualFold(in.CR.TargetEnv, want) {
		return Result{"R5", false, fmt.Sprintf(
			"变更单 %s 的目标环境是 `%s`，但本 PR 的目标分支 `%s` 对应 `%s`",
			in.CR.Number, in.CR.TargetEnv, in.PR.BaseRef, want)}
	}
	return Result{"R5", true, fmt.Sprintf("目标环境匹配：`%s`", want)}
}

// ── R6：变更单有效期覆盖当前时刻 ──────────────────────────
func ruleR6(_ context.Context, _ *Engine, in Input) Result {
	if in.CR == nil {
		return Result{"R6", false, "变更单不存在，无法检查有效期"}
	}
	if !in.CR.ValidFrom.IsZero() && in.Now.Before(in.CR.ValidFrom) {
		return Result{"R6", false, fmt.Sprintf(
			"变更单 %s 尚未生效（生效时间 %s，当前 %s）",
			in.CR.Number, in.CR.ValidFrom.Format(time.RFC3339), in.Now.Format(time.RFC3339))}
	}
	if !in.CR.ValidTo.IsZero() && in.Now.After(in.CR.ValidTo) {
		return Result{"R6", false, fmt.Sprintf(
			"变更单 %s 已过期（有效期至 %s，当前 %s）",
			in.CR.Number, in.CR.ValidTo.Format(time.RFC3339), in.Now.Format(time.RFC3339))}
	}
	valid := "永久有效"
	if !in.CR.ValidTo.IsZero() {
		valid = "有效期至 " + in.CR.ValidTo.Format(time.RFC3339)
	}
	return Result{"R6", true, fmt.Sprintf("变更单 %s 在有效期内（%s）", in.CR.Number, valid)}
}

// ── R6w：维护窗口 ─────────────────────────────────────────
func ruleR6w(_ context.Context, e *Engine, in Input) Result {
	env := e.cfg.EnvForBranch(in.PR.BaseRef)
	w, ok := e.windows[env]
	if !ok {
		return Result{"R6w", true, fmt.Sprintf("环境 `%s` 未配置维护窗口（不做时间限制）", env)}
	}
	if w.Contains(in.Now) {
		return Result{"R6w", true, fmt.Sprintf("当前在维护窗口内：%s", w.Describe())}
	}
	return Result{"R6w", false, fmt.Sprintf(
		"当前不在维护窗口内（窗口：%s，当前 %s）", w.Describe(), in.Now.In(w.Loc).Format("2006-01-02 15:04:05 MST"))}
}

// ── R7：变更单未被其他 PR 占用 ────────────────────────────
func ruleR7(_ context.Context, e *Engine, in Input) Result {
	num := in.Extraction.First()
	if num == "" {
		return Result{"R7", true, "没有变更单号，跳过唯一性检查"}
	}
	if e.usage.Claim(num, in.PR.Key()) {
		return Result{"R7", true, fmt.Sprintf("变更单 %s 未被其他 PR 占用", num)}
	}
	owner, _ := e.usage.Owner(num)
	return Result{"R7", false, fmt.Sprintf("变更单 %s 已被 %s 占用（防重复上线）", num, owner)}
}

// containsFold 大小写不敏感地判断切片是否包含某值。
func containsFold(list []string, v string) bool {
	for _, x := range list {
		if strings.EqualFold(x, v) {
			return true
		}
	}
	return false
}
