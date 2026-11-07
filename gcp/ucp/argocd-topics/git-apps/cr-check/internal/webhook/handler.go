package webhook

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/acme/cr-check/internal/audit"
	"github.com/acme/cr-check/internal/check"
	"github.com/acme/cr-check/internal/config"
	"github.com/acme/cr-check/internal/crplatform"
	"github.com/acme/cr-check/internal/observability"
	"github.com/acme/cr-check/internal/queue"
	"github.com/acme/cr-check/internal/recheck"
	"github.com/acme/cr-check/internal/rules"
)

// Handler 是 webhook 接收端。
type Handler struct {
	Cfg         *config.Config
	Engine      *rules.Engine
	CRClient    crplatform.Client
	Writer      check.Writer
	Store       queue.Store
	Audit       *audit.Sink
	Metrics     *observability.Metrics
	Logger      *slog.Logger
	Registry    *recheck.Registry
	Queue       *queue.Queue
	SyncEval    bool
	DeliveryTTL time.Duration
	// Clock 返回"当前时间"。生产用 time.Now；
	// 本地可以用 -now 参数固定时间，方便验证维护窗口规则。
	Clock func() time.Time
}

// now 返回当前时间（可被覆盖）。
func (h *Handler) now() time.Time {
	if h.Clock != nil {
		return h.Clock()
	}
	return time.Now()
}

// ── payload 结构（用我们自己的结构体，更宽容）────────────────

type pullRequestEvent struct {
	Action      string `json:"action"`
	Number      int    `json:"number"`
	PullRequest struct {
		Number int    `json:"number"`
		Title  string `json:"title"`
		Body   string `json:"body"`
		Base   struct {
			Ref  string `json:"ref"`
			Repo struct {
				FullName string `json:"full_name"`
			} `json:"repo"`
		} `json:"base"`
		Head struct {
			SHA string `json:"sha"`
		} `json:"head"`
		User struct {
			Login string `json:"login"`
		} `json:"user"`
		Labels []struct {
			Name string `json:"name"`
		} `json:"labels"`
	} `json:"pull_request"`
	Repository struct {
		Name     string `json:"name"`
		FullName string `json:"full_name"`
		Owner    struct {
			Login string `json:"login"`
		} `json:"owner"`
	} `json:"repository"`
	Installation struct {
		ID int64 `json:"id"`
	} `json:"installation"`
}

// pullRequestActions 是会触发判定的 action 集合。
var pullRequestActions = map[string]bool{
	"opened": true, "synchronize": true, "reopened": true,
	"labeled": true, "unlabeled": true, "ready_for_review": true, "edited": true,
}

// ServeHTTP 是唯一入口。
//
// 处理顺序：限流/读体 → 验签 → 幂等 → 事件白名单 → 分发。
func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{"error": "只接受 POST"})
		return
	}

	body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, h.Cfg.Webhook.MaxBodyBytes))
	if err != nil {
		h.Metrics.WebhookRejected.WithLabelValues("read_body").Inc()
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": "读取请求体失败: " + err.Error()})
		return
	}

	// ① 验签
	if err := VerifySignature(h.Cfg.WebhookSecretBytes(), body, r.Header.Get("X-Hub-Signature-256")); err != nil {
		h.Metrics.WebhookRejected.WithLabelValues("bad_signature").Inc()
		h.Logger.Warn("webhook 验签失败", "remote", r.RemoteAddr, "err", err)
		writeJSON(w, http.StatusUnauthorized, map[string]any{"error": err.Error()})
		return
	}

	event := r.Header.Get("X-GitHub-Event")
	delivery := r.Header.Get("X-GitHub-Delivery")

	// ② 幂等（GitHub 会重投）
	if delivery != "" {
		seen, err := h.Store.Seen(r.Context(), delivery)
		if err != nil {
			h.Logger.Error("幂等检查失败", "err", err)
		} else if seen {
			h.Metrics.WebhookRejected.WithLabelValues("duplicate").Inc()
			writeJSON(w, http.StatusOK, map[string]any{
				"status": "duplicate", "reason": "该 delivery id 已处理过", "delivery_id": delivery,
			})
			return
		}
		ttl := h.DeliveryTTL
		if ttl <= 0 {
			ttl = 24 * time.Hour
		}
		if err := h.Store.Remember(r.Context(), delivery, ttl); err != nil {
			h.Logger.Error("写入幂等键失败", "err", err)
		}
	}

	// ③ ping 事件（GitHub 在你保存 Webhook URL 时发的那条）→ 总是接受
	if event == "ping" {
		h.Metrics.WebhookReceived.WithLabelValues("ping", "").Inc()
		writeJSON(w, http.StatusOK, map[string]any{"status": "pong"})
		return
	}

	// ④ 事件白名单
	if !h.eventAllowed(event) {
		h.Metrics.WebhookReceived.WithLabelValues(event, "").Inc()
		writeJSON(w, http.StatusOK, map[string]any{
			"status": "ignored", "reason": "事件类型未订阅: " + event, "event": event,
		})
		return
	}

	switch event {
	case "pull_request":
		h.handlePullRequest(w, r, body, delivery)
		return
	default:
		h.Metrics.WebhookReceived.WithLabelValues(event, "").Inc()
		writeJSON(w, http.StatusOK, map[string]any{
			"status": "ignored", "reason": "该事件本版本不处理", "event": event,
		})
	}
}

// eventAllowed 判断事件是否在订阅白名单里。
func (h *Handler) eventAllowed(event string) bool {
	for _, e := range h.Cfg.Webhook.Events {
		if e == event {
			return true
		}
	}
	return false
}

// handlePullRequest 处理 PR 事件。
func (h *Handler) handlePullRequest(w http.ResponseWriter, r *http.Request, body []byte, delivery string) {
	var ev pullRequestEvent
	if err := json.Unmarshal(body, &ev); err != nil {
		h.Metrics.WebhookRejected.WithLabelValues("bad_payload").Inc()
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": "解析 payload 失败: " + err.Error()})
		return
	}
	h.Metrics.WebhookReceived.WithLabelValues("pull_request", ev.Action).Inc()

	// action 白名单
	if !pullRequestActions[ev.Action] {
		writeJSON(w, http.StatusOK, map[string]any{
			"status": "ignored", "reason": "action 不触发判定: " + ev.Action, "action": ev.Action,
		})
		return
	}

	pr := h.toPRInfo(&ev)

	// ★ 分支过滤必须放在最前面：非受管分支不产生 check，
	// 否则会污染 PR 列表、消耗配额，而且非生产分支本不需要变更单。
	if !h.Cfg.IsManagedBranch(pr.BaseRef) {
		writeJSON(w, http.StatusOK, map[string]any{
			"status": "ignored", "reason": "base 分支不在受管清单内",
			"base_ref": pr.BaseRef, "managed_branches": h.Cfg.ManagedBranches,
		})
		return
	}

	// 记录到 registry（供定时重扫使用）
	h.Registry.Add(pr)

	// 把 installation id 放进 context（写 check 时要用它换 installation token）
	ctx := check.WithInstallationID(r.Context(), ev.Installation.ID)

	// 异步模式：先 ACK，判定交给后台 worker
	if !h.SyncEval {
		job := queue.Job{Event: "pull_request", DeliveryID: delivery, Payload: body, ReceivedAt: time.Now()}
		if !h.Queue.Push(job) {
			h.Logger.Error("队列已满，任务被丢弃", "delivery_id", delivery)
			writeJSON(w, http.StatusServiceUnavailable, map[string]any{
				"status": "queue_full", "error": "判定队列已满，请稍后重试",
			})
			return
		}
		h.Metrics.QueueDepth.Set(float64(h.Queue.Depth()))
		writeJSON(w, http.StatusAccepted, map[string]any{
			"status": "queued", "pr": pr.Number, "repo": pr.Repo, "head_sha": pr.HeadSHA,
		})
		return
	}

	// 同步模式（本地调试）：直接判定并把结论返回
	outcome := h.Evaluate(ctx, pr, delivery, "webhook")
	resp := map[string]any{
		"status":       "evaluated",
		"event":        "pull_request",
		"action":       ev.Action,
		"repo":         pr.Owner + "/" + pr.Repo,
		"pr":           pr.Number,
		"head_sha":     pr.HeadSHA,
		"base_ref":     pr.BaseRef,
		"env":          outcome.Env,
		"cr_number":    outcome.CRNumber,
		"conclusion":   outcome.Conclusion(),
		"ok":           outcome.OK,
		"system_error": outcome.SystemError,
		"failed_rules": outcome.FailedIDs(),
		"rules":        outcome.Results,
		"summary":      outcome.Render(),
		"delivery_id":  delivery,
	}
	writeJSON(w, http.StatusOK, resp)
}

// toPRInfo 从事件里抽出 PR 快照。
func (h *Handler) toPRInfo(ev *pullRequestEvent) rules.PRInfo {
	owner := ev.Repository.Owner.Login
	repo := ev.Repository.Name
	if owner == "" || repo == "" {
		if i := strings.Index(ev.Repository.FullName, "/"); i > 0 {
			owner, repo = ev.Repository.FullName[:i], ev.Repository.FullName[i+1:]
		}
	}
	labels := make([]string, 0, len(ev.PullRequest.Labels))
	for _, l := range ev.PullRequest.Labels {
		labels = append(labels, l.Name)
	}
	num := ev.PullRequest.Number
	if num == 0 {
		num = ev.Number
	}
	return rules.PRInfo{
		Number:    num,
		Owner:     owner,
		Repo:      repo,
		BaseRef:   ev.PullRequest.Base.Ref,
		HeadSHA:   ev.PullRequest.Head.SHA,
		Requester: ev.PullRequest.User.Login,
		Labels:    labels,
		Body:      ev.PullRequest.Body,
		Title:     ev.PullRequest.Title,
	}
}

// Evaluate 执行一次完整判定，并把结论写回 check。
//
// ★ 系统异常（CR 平台不可用）**不得写 success** —— 一律 failure + 告警。
func (h *Handler) Evaluate(ctx context.Context, pr rules.PRInfo, deliveryID, source string) rules.Outcome {
	start := time.Now()
	h.Logger.Info("开始判定", "pr", pr.Key(), "base", pr.BaseRef, "sha", pr.HeadSHA, "source", source)
	defer func() {
		h.Metrics.EvaluationTime.Observe(time.Since(start).Seconds())
	}()

	ex := rules.ExtractCRNumbers(pr.Labels, pr.Body,
		h.Cfg.CR.LabelPattern, h.Cfg.CR.LabelPrefix, h.Cfg.CR.BodyMarker)

	ref := check.Ref{
		Owner: pr.Owner, Repo: pr.Repo, SHA: pr.HeadSHA, Name: h.Cfg.CheckName,
	}

	// 步骤④：先置 in_progress（评估期间合并被正确阻断）
	if err := h.Writer.MarkInProgress(ctx, ref, "正在校验变更单…"); err != nil {
		h.Logger.Error("写 in_progress 失败", "err", err)
	}
	h.Metrics.ChecksWritten.Inc()

	var (
		cr  *crplatform.ChangeRequest
		sys rules.Outcome
	)
	crNumber := ex.First()
	if crNumber != "" {
		got, err := h.CRClient.Get(ctx, crNumber)
		if err != nil {
			// ★ 系统异常：fail-closed
			h.Metrics.CRPlatformCalls.WithLabelValues("error").Inc()
			h.Logger.Error("调用 CR 平台失败（系统异常）", "cr", crNumber, "err", err)
			sys = rules.Outcome{
				OK: false, SystemError: true, SystemMessage: err.Error(),
				CRNumber: crNumber, Env: h.Cfg.EnvForBranch(pr.BaseRef), EvaluatedAt: time.Now(),
			}
			h.writeOutcome(ctx, ref, sys, pr, deliveryID, source)
			h.alert(sys, pr)
			return sys
		}
		h.Metrics.CRPlatformCalls.WithLabelValues("ok").Inc()
		cr = got
	} else {
		h.Metrics.CRPlatformCalls.WithLabelValues("skipped").Inc()
	}

	in := rules.Input{
		PR: pr, CR: cr, Extraction: ex, Now: h.now(), Policy: h.Cfg,
	}
	outcome := h.Engine.Evaluate(ctx, in)
	h.writeOutcome(ctx, ref, outcome, pr, deliveryID, source)
	return outcome
}

// writeOutcome 把结论写进 check 并做审计与指标。
func (h *Handler) writeOutcome(ctx context.Context, ref check.Ref, outcome rules.Outcome, pr rules.PRInfo, deliveryID, source string) {
	if err := h.Writer.Complete(ctx, ref, outcome); err != nil {
		h.Logger.Error("写 check 结论失败", "err", err)
		h.Metrics.GitHubAPIErrors.WithLabelValues("check_write").Inc()
	}
	h.Metrics.ChecksWritten.Inc()
	h.Metrics.JobsTotal.WithLabelValues(outcome.Conclusion()).Inc()
	for _, id := range outcome.FailedIDs() {
		h.Metrics.RuleFailed.WithLabelValues(id).Inc()
	}
	h.Audit.Record(audit.Event{
		Kind:        "evaluation",
		Repo:        pr.Owner + "/" + pr.Repo,
		PR:          pr.Number,
		HeadSHA:     pr.HeadSHA,
		BaseRef:     pr.BaseRef,
		Env:         outcome.Env,
		CRNumber:    outcome.CRNumber,
		Conclusion:  outcome.Conclusion(),
		SystemError: outcome.SystemError,
		FailedRules: outcome.FailedIDs(),
		DeliveryID:  deliveryID,
		Source:      source,
	})
}

// alert 在系统异常时告警。
//
// ★ "读到了但没写出去"必须是一个独立告警，不能靠间接现象发现。
func (h *Handler) alert(o rules.Outcome, pr rules.PRInfo) {
	h.Logger.Error("⚠️ 门禁系统异常（fail-closed），需要人工介入",
		"pr", pr.Key(), "error", o.SystemMessage, "action", "检查 CR 平台可用性与网络出网")
}

// writeJSON 写 JSON 响应。
func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	_ = enc.Encode(body)
}

// WriteJSON 是 writeJSON 的导出版本（给其它包用）。
func WriteJSON(w http.ResponseWriter, status int, body any) { writeJSON(w, status, body) }

// Describe 把 handler 的关键配置打印出来（启动日志用）。
func (h *Handler) Describe() string {
	return fmt.Sprintf("check=%s sync=%v managed=%v", h.Cfg.CheckName, h.SyncEval, h.Cfg.ManagedBranches)
}
