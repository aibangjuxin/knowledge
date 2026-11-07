// Command server 是 CR Check 的入口。
//
// 两种运行模式：
//   - mock：本地调试用。内置假 CR 平台 + 日志型 check writer + 同步判定。
//   - real：生产用。真实的 CR 平台 HTTP 客户端 + GitHub Checks API + 异步判定。
package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/acme/cr-check/internal/audit"
	"github.com/acme/cr-check/internal/check"
	"github.com/acme/cr-check/internal/config"
	"github.com/acme/cr-check/internal/crplatform"
	"github.com/acme/cr-check/internal/gh"
	"github.com/acme/cr-check/internal/observability"
	"github.com/acme/cr-check/internal/queue"
	"github.com/acme/cr-check/internal/recheck"
	"github.com/acme/cr-check/internal/rules"
	"github.com/acme/cr-check/internal/webhook"
)

func main() {
	var (
		configPath = flag.String("config", "config/policy.yaml", "策略配置文件路径")
		addr       = flag.String("addr", "", "监听地址（覆盖配置文件里的 server.addr）")
		mode       = flag.String("mode", "auto", "运行模式：auto | mock | real")
		syncEval   = flag.Bool("sync-eval", false, "在 webhook handler 里同步完成判定（本地调试用；生产必须 false）")
		auditFile  = flag.String("audit-file", "", "审计日志文件路径（追加 JSON 行）")
		nowFlag    = flag.String("now", "", `固定"当前时间"（RFC3339），用于本地验证维护窗口规则；留空 = 真实时间`)
		showConfig = flag.Bool("show-config", false, "打印生效配置后退出")
	)
	flag.Parse()

	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))
	slog.SetDefault(logger)

	if err := run(logger, *configPath, *addr, *mode, *syncEval, *auditFile, *showConfig, *nowFlag); err != nil {
		logger.Error("启动失败", "err", err)
		os.Exit(1)
	}
}

func run(logger *slog.Logger, configPath, addr, mode string, syncEval bool, auditFile string, showConfig bool, nowFlag string) error {
	cfg, err := config.Load(configPath)
	if err != nil {
		return err
	}
	if addr != "" {
		cfg.Server.Addr = addr
	}

	// ── 决定运行模式 ────────────────────────────────────────
	if mode == "auto" {
		if cfg.HasGitHubCredentials() && cfg.HasCRPlatform() {
			mode = "real"
		} else {
			mode = "mock"
		}
	}
	if mode == "mock" && !syncEval {
		// mock 模式默认同步判定，方便 curl 立刻看到结论
		syncEval = true
	}
	if mode == "real" && syncEval {
		logger.Warn("real 模式不建议开启 -sync-eval（生产应先 ACK 再异步判定）")
	}

	logger.Info("启动 CR Check",
		"mode", mode, "addr", cfg.Server.Addr, "check", cfg.CheckName,
		"managed_branches", cfg.ManagedBranches, "sync_eval", syncEval,
		"github_configured", cfg.HasGitHubCredentials(),
		"cr_platform_configured", cfg.HasCRPlatform())

	if showConfig {
		b, _ := json.MarshalIndent(cfg.Redacted(), "", "  ")
		fmt.Println(string(b))
		return nil
	}

	// ── 依赖组装 ────────────────────────────────────────────
	metrics := observability.New()

	engine, err := rules.NewEngine(cfg)
	if err != nil {
		return fmt.Errorf("构造判定引擎: %w", err)
	}

	auditSink, err := audit.NewSink(logger, auditFile)
	if err != nil {
		return fmt.Errorf("构造审计 sink: %w", err)
	}
	defer func() {
		if err := auditSink.Close(); err != nil {
			logger.Warn("关闭审计文件失败", "err", err)
		}
	}()

	// CR 平台客户端
	var crClient crplatform.Client
	var mockCR *crplatform.MockClient
	if mode == "mock" {
		mockCR = crplatform.NewMockClient(cfg.CR.StatusAliases)
		for _, m := range cfg.Mock.CRs {
			if m.Error != "" {
				mockCR.AddError(m.Number, errors.New(m.Error))
				continue
			}
			cr := &crplatform.ChangeRequest{
				Number:    m.Number,
				Status:    crplatform.NormalizeStatus(m.Status, cfg.CR.StatusAliases),
				Requester: m.Requester,
				TargetEnv: m.TargetEnv,
				URL:       m.URL,
			}
			for _, a := range m.Approvers {
				cr.Approvers = append(cr.Approvers, crplatform.Approval{
					Approver: a, Decision: "approve", DecidedAt: time.Now(),
				})
			}
			if m.ValidFrom != "" {
				cr.ValidFrom, _ = time.Parse(time.RFC3339, m.ValidFrom)
			}
			if m.ValidTo != "" {
				cr.ValidTo, _ = time.Parse(time.RFC3339, m.ValidTo)
			}
			mockCR.Add(cr)
		}
		crClient = mockCR
		logger.Info("mock 模式：使用内置假 CR 平台", "crs", len(cfg.Mock.CRs))
	} else {
		crClient = crplatform.NewHTTPClient(
			cfg.CRPlatform.BaseURL, cfg.CRPlatform.Token, cfg.CRPlatform.Path,
			time.Duration(cfg.CRPlatform.TimeoutSeconds)*time.Second, cfg.CR.StatusAliases)
	}

	// check writer
	var writer check.Writer
	if mode == "mock" {
		writer = check.NewLogWriter(logger)
	} else {
		if !cfg.HasGitHubCredentials() {
			return errors.New("real 模式需要 GITHUB_APP_ID / GITHUB_APP_INSTALLATION_ID / GITHUB_APP_PRIVATE_KEY_PATH")
		}
		writer = check.NewGitHubWriter(gh.NewFactory(&cfg.GitHub), logger)
	}

	// 幂等存储（本地用内存；生产换 Redis）
	store := queue.NewMemoryStore()

	registry := recheck.NewRegistry()
	jobQueue := queue.NewQueue(256, cfg.Server.Workers)

	// 可选的固定时间（本地验证维护窗口用）
	clock := time.Now
	if nowFlag != "" {
		fixed, err := time.Parse(time.RFC3339, nowFlag)
		if err != nil {
			return fmt.Errorf("解析 -now %q: %w", nowFlag, err)
		}
		clock = func() time.Time { return fixed }
		logger.Warn("使用固定时间（本地调试）", "now", fixed.Format(time.RFC3339))
	}

	handler := &webhook.Handler{
		Cfg:         cfg,
		Engine:      engine,
		CRClient:    crClient,
		Writer:      writer,
		Store:       store,
		Audit:       auditSink,
		Metrics:     metrics,
		Logger:      logger,
		Registry:    registry,
		Queue:       jobQueue,
		SyncEval:    syncEval,
		DeliveryTTL: 24 * time.Hour,
		Clock:       clock,
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	// 异步 worker
	jobQueue.Start(ctx, func(j queue.Job) {
		var ev struct {
			PullRequest struct {
				Number int    `json:"number"`
				Title  string `json:"title"`
				Body   string `json:"body"`
				Base   struct {
					Ref string `json:"ref"`
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
				Name  string `json:"name"`
				Owner struct {
					Login string `json:"login"`
				} `json:"owner"`
			} `json:"repository"`
			Installation struct {
				ID int64 `json:"id"`
			} `json:"installation"`
		}
		if err := json.Unmarshal(j.Payload, &ev); err != nil {
			logger.Error("解析队列任务失败", "err", err)
			return
		}
		labels := make([]string, 0, len(ev.PullRequest.Labels))
		for _, l := range ev.PullRequest.Labels {
			labels = append(labels, l.Name)
		}
		pr := rules.PRInfo{
			Number: ev.PullRequest.Number, Owner: ev.Repository.Owner.Login, Repo: ev.Repository.Name,
			BaseRef: ev.PullRequest.Base.Ref, HeadSHA: ev.PullRequest.Head.SHA,
			Requester: ev.PullRequest.User.Login, Labels: labels, Body: ev.PullRequest.Body,
			Title: ev.PullRequest.Title,
		}
		hctx := check.WithInstallationID(context.Background(), ev.Installation.ID)
		outcome := handler.Evaluate(hctx, pr, j.DeliveryID, "webhook-async")
		registry.SetConclusion(pr.Key(), outcome.Conclusion())
		metrics.QueueDepth.Set(float64(jobQueue.Depth()))
	})

	// 定时重扫（兜底：事件丢失 + 维护窗口过期）
	scheduler := recheck.NewScheduler(registry, func(c context.Context, pr rules.PRInfo) (rules.Outcome, error) {
		outcome := handler.Evaluate(c, pr, "", "recheck")
		registry.SetConclusion(pr.Key(), outcome.Conclusion())
		return outcome, nil
	}, time.Duration(cfg.Server.RecheckIntervalSeconds)*time.Second, logger)
	scheduler.OnScanned = func(n int) { metrics.RecheckScanned.Add(float64(n)) }
	scheduler.OnFlipped = func() { metrics.RecheckFlipped.Inc() }
	go scheduler.Run(ctx)

	// ── HTTP 路由 ───────────────────────────────────────────
	mux := http.NewServeMux()
	mux.Handle("POST /github/webhook", handler)

	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok\n"))
	})

	mux.HandleFunc("GET /readyz", func(w http.ResponseWriter, r *http.Request) {
		// readiness 要包含"能拿到 installation token"，
		// 否则私钥/网络故障时 Pod 仍然 Ready → 请求全失败
		ready := map[string]any{"ready": true, "mode": mode}
		if mode == "real" {
			ready["github_credentials"] = cfg.HasGitHubCredentials()
			ready["cr_platform"] = cfg.HasCRPlatform()
		}
		webhook.WriteJSON(w, http.StatusOK, ready)
	})

	mux.Handle("GET /metrics", metrics.Handler())

	mux.HandleFunc("GET /internal/policy", func(w http.ResponseWriter, r *http.Request) {
		webhook.WriteJSON(w, http.StatusOK, cfg.Redacted())
	})

	mux.HandleFunc("GET /internal/last-check", func(w http.ResponseWriter, r *http.Request) {
		lw, ok := writer.(*check.LogWriter)
		if !ok {
			webhook.WriteJSON(w, http.StatusOK, map[string]any{
				"note": "real 模式下没有本地记录，请去 GitHub PR 上看 check run",
			})
			return
		}
		webhook.WriteJSON(w, http.StatusOK, lw.Last())
	})

	mux.HandleFunc("GET /internal/audit", func(w http.ResponseWriter, r *http.Request) {
		webhook.WriteJSON(w, http.StatusOK, auditSink.Recent(50))
	})

	mux.HandleFunc("GET /internal/registry", func(w http.ResponseWriter, r *http.Request) {
		webhook.WriteJSON(w, http.StatusOK, registry.List())
	})

	mux.HandleFunc("POST /internal/recheck", func(w http.ResponseWriter, r *http.Request) {
		scheduler.RunOnce(r.Context())
		webhook.WriteJSON(w, http.StatusOK, map[string]any{
			"status": "recheck done", "prs": len(registry.List()), "flipped": scheduler.Flipped(),
		})
	})

	if mockCR != nil {
		mux.Handle("GET /mock/cr/{number}", mockCR.Handler("/mock/cr/"))
	}

	mux.HandleFunc("GET /", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		_, _ = w.Write([]byte(indexPage(cfg, mode, syncEval)))
	})

	srv := &http.Server{
		Addr:              cfg.Server.Addr,
		Handler:           mux,
		ReadHeaderTimeout: 10 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	go func() {
		logger.Info("HTTP 服务已启动", "addr", cfg.Server.Addr, "index", "http://localhost"+cfg.Server.Addr+"/")
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logger.Error("HTTP 服务退出", "err", err)
			stop()
		}
	}()

	<-ctx.Done()
	logger.Info("收到退出信号，开始优雅关闭")
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	return srv.Shutdown(shutdownCtx)
}

// indexPage 是首页（给本地验证用）。
func indexPage(cfg *config.Config, mode string, syncEval bool) string {
	var b strings.Builder
	b.WriteString("CR Check · GitHub App 后端服务\n")
	b.WriteString("================================\n\n")
	fmt.Fprintf(&b, "运行模式 : %s（sync-eval=%v）\n", mode, syncEval)
	fmt.Fprintf(&b, "check 名字: %s\n", cfg.CheckName)
	fmt.Fprintf(&b, "受管分支  : %v\n", cfg.ManagedBranches)
	fmt.Fprintf(&b, "分支→环境 : %v\n\n", cfg.BranchEnvMap)

	b.WriteString("端点：\n")
	b.WriteString("  POST /github/webhook     ← GitHub 事件入口（验签 → 幂等 → 判定 → 写 check）\n")
	b.WriteString("  GET  /healthz           ← 存活探针\n")
	b.WriteString("  GET  /readyz            ← 就绪探针\n")
	b.WriteString("  GET  /metrics           ← Prometheus 指标\n")
	b.WriteString("  GET  /internal/policy   ← 生效配置（脱敏）\n")
	b.WriteString("  GET  /internal/last-check ← 最近一次 check 写入\n")
	b.WriteString("  GET  /internal/audit    ← 最近 50 条审计\n")
	b.WriteString("  GET  /internal/registry ← 已登记的受管 PR\n")
	b.WriteString("  POST /internal/recheck   ← 立即触发一次定时重扫\n")
	if mode == "mock" {
		b.WriteString("  GET  /mock/cr/{number}  ← 内置假 CR 平台（查看 mock 数据）\n")
	}
	b.WriteString("\n快速验证：\n")
	b.WriteString("  curl -s -X POST http://localhost:8080/github/webhook \\\n")
	b.WriteString("    -H 'X-GitHub-Event: pull_request' \\\n")
	b.WriteString("    -H 'X-GitHub-Delivery: demo-1' \\\n")
	b.WriteString("    -H 'Content-Type: application/json' \\\n")
	b.WriteString("    --data @testdata/pr-event.json | jq\n")
	return b.String()
}
