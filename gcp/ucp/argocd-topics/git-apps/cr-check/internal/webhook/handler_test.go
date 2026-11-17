package webhook

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"
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

// newTestHandler 组装一个 mock 模式的 handler。
func newTestHandler(t *testing.T) (*Handler, *check.LogWriter) {
	t.Helper()

	cfg := &config.Config{
		CheckName:       "cr/prod-validation",
		Timezone:        "Asia/Shanghai",
		ManagedBranches: []string{"release/prd", "release/prod"},
		BranchEnvMap: map[string]string{
			"release/prd":  "prd",
			"release/prod": "prod",
		},
		CR: config.CRConfig{
			AllowedExecutableStatuses: []string{"approved", "implement"},
			StatusAliases: map[string][]string{
				"draft":     {"Draft"},
				"approved":  {"Approved"},
				"implement": {"Implement"},
			},
			MinApprovals:       2,
			ForbidSelfApproval: true,
			AllowedApprovers:   []string{"bob", "carol"},
			LabelPrefix:        "cr/",
			LabelPattern:       `^cr/[0-9A-Za-z._-]+$`,
			BodyMarker:         "Change-Request:",
		},
		Webhook: config.WebhookConfig{
			Secret:       "",
			Events:       []string{"pull_request"},
			MaxBodyBytes: 1 << 20,
		},
		Server: config.ServerConfig{Addr: ":0", SyncEval: true, Workers: 1},
	}
	if err := cfg.Validate(); err != nil {
		t.Fatalf("配置校验失败: %v", err)
	}

	engine, err := rules.NewEngine(cfg)
	if err != nil {
		t.Fatalf("构造引擎失败: %v", err)
	}

	mock := crplatform.NewMockClient(cfg.CR.StatusAliases)
	mock.Add(&crplatform.ChangeRequest{
		Number: "1234", Status: crplatform.StatusImplement, Requester: "alice",
		TargetEnv: "prd",
		Approvers: []crplatform.Approval{
			{Approver: "bob", Decision: "approve"},
			{Approver: "carol", Decision: "approve"},
		},
		ValidFrom: time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC),
		ValidTo:   time.Date(2035, 12, 31, 0, 0, 0, 0, time.UTC),
	})
	mock.Add(&crplatform.ChangeRequest{
		Number: "5678", Status: crplatform.StatusDraft, Requester: "alice",
		TargetEnv: "prd",
		Approvers: []crplatform.Approval{{Approver: "bob", Decision: "approve"}},
		ValidFrom: time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC),
		ValidTo:   time.Date(2035, 12, 31, 0, 0, 0, 0, time.UTC),
	})
	mock.AddError("9999", context.DeadlineExceeded)

	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	sink, _ := audit.NewSink(logger, "")
	lw := check.NewLogWriter(logger)

	h := &Handler{
		Cfg:      cfg,
		Engine:   engine,
		CRClient: mock,
		Writer:   lw,
		Store:    queue.NewMemoryStore(),
		Audit:    sink,
		Metrics:  observability.New(),
		Logger:   logger,
		Registry: recheck.NewRegistry(),
		Queue:    queue.NewQueue(16, 1),
		SyncEval: true,
		Clock: func() time.Time {
			return time.Date(2025, 1, 6, 3, 0, 0, 0, time.FixedZone("CST", 8*3600))
		},
	}
	return h, lw
}

// payload 构造一个 pull_request 事件。
func payload(crNumber, baseRef string) []byte {
	return []byte(`{
  "action": "opened",
  "number": 42,
  "pull_request": {
    "number": 42,
    "title": "t",
    "body": "Change-Request: ` + crNumber + `",
    "base": { "ref": "` + baseRef + `" },
    "head": { "sha": "abc123" },
    "user": { "login": "alice" },
    "labels": [ { "name": "cr/` + crNumber + `" } ]
  },
  "repository": { "name": "platform", "owner": { "login": "acme" } },
  "installation": { "id": 1 }
}`)
}

func post(h *Handler, body []byte, delivery string) (int, map[string]any) {
	r := httptest.NewRequest(http.MethodPost, "/github/webhook", bytes.NewReader(body))
	r.Header.Set("X-GitHub-Event", "pull_request")
	r.Header.Set("X-GitHub-Delivery", delivery)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)

	var out map[string]any
	_ = json.Unmarshal(w.Body.Bytes(), &out)
	return w.Code, out
}

func TestHandler_HappyPath(t *testing.T) {
	h, _ := newTestHandler(t)
	code, out := post(h, payload("1234", "release/prd"), "d1")

	if code != http.StatusOK {
		t.Fatalf("HTTP %d，期望 200", code)
	}
	if out["conclusion"] != "success" {
		t.Fatalf("conclusion = %v，期望 success（完整响应 %v）", out["conclusion"], out)
	}
	if out["cr_number"] != "1234" {
		t.Errorf("cr_number = %v，期望 1234", out["cr_number"])
	}
}

func TestHandler_RuleFailure(t *testing.T) {
	h, _ := newTestHandler(t)
	_, out := post(h, payload("5678", "release/prd"), "d2")

	if out["conclusion"] != "failure" {
		t.Fatalf("conclusion = %v，期望 failure", out["conclusion"])
	}
	failed, _ := out["failed_rules"].([]any)
	var hasR3 bool
	for _, f := range failed {
		if f == "R3" {
			hasR3 = true
		}
	}
	if !hasR3 {
		t.Errorf("failed_rules = %v，期望包含 R3", failed)
	}
}

func TestHandler_SystemErrorFailsClosed(t *testing.T) {
	h, _ := newTestHandler(t)
	_, out := post(h, payload("9999", "release/prd"), "d3")

	if out["system_error"] != true {
		t.Fatalf("system_error = %v，期望 true", out["system_error"])
	}
	// ★ 绝不能是 success
	if out["conclusion"] == "success" {
		t.Fatalf("系统异常时结论不能是 success（这是门禁被打开）")
	}
	if out["conclusion"] != "failure" {
		t.Errorf("conclusion = %v，期望 failure", out["conclusion"])
	}
}

func TestHandler_UnmanagedBranchIgnored(t *testing.T) {
	h, _ := newTestHandler(t)
	_, out := post(h, payload("1234", "feature/x"), "d4")

	if out["status"] != "ignored" {
		t.Fatalf("status = %v，期望 ignored", out["status"])
	}
	if _, ok := out["conclusion"]; ok {
		t.Errorf("非受管分支不应该产生 conclusion")
	}
}

func TestHandler_Idempotency(t *testing.T) {
	h, _ := newTestHandler(t)
	body := payload("1234", "release/prd")

	_, first := post(h, body, "same-delivery")
	if first["status"] != "evaluated" {
		t.Fatalf("第一次 status = %v，期望 evaluated", first["status"])
	}
	_, second := post(h, body, "same-delivery")
	if second["status"] != "duplicate" {
		t.Fatalf("第二次 status = %v，期望 duplicate", second["status"])
	}
}

func TestHandler_MissingCRNumber(t *testing.T) {
	h, _ := newTestHandler(t)
	body := []byte(`{
  "action": "opened",
  "number": 7,
  "pull_request": {
    "number": 7, "body": "没有任何单号",
    "base": { "ref": "release/prd" }, "head": { "sha": "abc" },
    "user": { "login": "alice" }, "labels": []
  },
  "repository": { "name": "platform", "owner": { "login": "acme" } }
}`)
	_, out := post(h, body, "d5")
	if out["conclusion"] != "failure" {
		t.Fatalf("conclusion = %v，期望 failure", out["conclusion"])
	}
	failed, _ := out["failed_rules"].([]any)
	var hasR1 bool
	for _, f := range failed {
		if f == "R1" {
			hasR1 = true
		}
	}
	if !hasR1 {
		t.Errorf("failed_rules = %v，期望包含 R1", failed)
	}
}

func TestHandler_Ping(t *testing.T) {
	h, _ := newTestHandler(t)
	r := httptest.NewRequest(http.MethodPost, "/github/webhook", bytes.NewReader([]byte(`{}`)))
	r.Header.Set("X-GitHub-Event", "ping")
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)

	if w.Code != http.StatusOK {
		t.Fatalf("HTTP %d，期望 200", w.Code)
	}
	var out map[string]any
	_ = json.Unmarshal(w.Body.Bytes(), &out)
	if out["status"] != "pong" {
		t.Errorf("status = %v，期望 pong", out["status"])
	}
}
