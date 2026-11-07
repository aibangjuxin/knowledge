// Package check 负责把判定结论写回 GitHub（Check Run）。
package check

import (
	"context"
	"fmt"
	"log/slog"
	"sync"
	"time"

	"github.com/acme/cr-check/internal/gh"
	"github.com/acme/cr-check/internal/rules"
	gogithub "github.com/google/go-github/v88/github"
)

// Ref 是一次 check 写入的目标。
type Ref struct {
	Owner string
	Repo  string
	SHA   string
	Name  string // check 名字，必须与 required status check 一致
}

// Writer 是 check 写入接口。
type Writer interface {
	// MarkInProgress 把 check 置为"评估中"。
	// 作用：① 同 SHA 重评时旧 success 不会冒充新结论；
	//       ② in_progress 不属于 successful/skipped/neutral → 合并被正确阻断。
	MarkInProgress(ctx context.Context, ref Ref, summary string) error

	// Complete 写终态结论（覆盖同名 check）。
	Complete(ctx context.Context, ref Ref, outcome rules.Outcome) error
}

// ─────────────────────────────────────────────────────────────
// LogWriter：本地 / mock 模式使用
// ─────────────────────────────────────────────────────────────

// Record 是一次 check 写入的记录。
type Record struct {
	Ref        Ref            `json:"ref"`
	Status     string         `json:"status"`
	Conclusion string         `json:"conclusion"`
	Title      string         `json:"title"`
	Summary    string         `json:"summary"`
	Rules      []rules.Result `json:"rules"`
	At         time.Time      `json:"at"`
}

// LogWriter 把 check 写入记到日志和内存里。
type LogWriter struct {
	mu     sync.Mutex
	last   *Record
	all    []*Record
	logger *slog.Logger
}

// NewLogWriter 构造日志 writer。
func NewLogWriter(logger *slog.Logger) *LogWriter {
	return &LogWriter{logger: logger}
}

// MarkInProgress 实现 Writer。
func (w *LogWriter) MarkInProgress(_ context.Context, ref Ref, summary string) error {
	return w.write(Record{
		Ref: ref, Status: "in_progress", Conclusion: "in_progress",
		Title: "变更单校验中", Summary: summary, At: time.Now(),
	})
}

// Complete 实现 Writer。
func (w *LogWriter) Complete(_ context.Context, ref Ref, outcome rules.Outcome) error {
	return w.write(Record{
		Ref: ref, Status: "completed", Conclusion: outcome.Conclusion(),
		Title: "变更单校验结果", Summary: outcome.Render(), Rules: outcome.Results, At: time.Now(),
	})
}

func (w *LogWriter) write(r Record) error {
	w.mu.Lock()
	w.last = &r
	w.all = append(w.all, &r)
	if len(w.all) > 200 {
		w.all = w.all[len(w.all)-200:]
	}
	w.mu.Unlock()

	w.logger.Info("check run written",
		"owner", r.Ref.Owner, "repo", r.Ref.Repo, "sha", r.Ref.SHA,
		"name", r.Ref.Name, "status", r.Status, "conclusion", r.Conclusion)
	return nil
}

// Last 返回最近一次写入的记录。
func (w *LogWriter) Last() *Record {
	w.mu.Lock()
	defer w.mu.Unlock()
	return w.last
}

// All 返回全部记录（调试用）。
func (w *LogWriter) All() []*Record {
	w.mu.Lock()
	defer w.mu.Unlock()
	out := make([]*Record, len(w.all))
	copy(out, w.all)
	return out
}

// ─────────────────────────────────────────────────────────────
// GitHubWriter：真实写入 GitHub Checks API
// ─────────────────────────────────────────────────────────────

// GitHubWriter 通过 GitHub Checks API 写入 check run。
type GitHubWriter struct {
	factory *gh.Factory
	logger  *slog.Logger
}

// NewGitHubWriter 构造真实 writer。
func NewGitHubWriter(f *gh.Factory, logger *slog.Logger) *GitHubWriter {
	return &GitHubWriter{factory: f, logger: logger}
}

// MarkInProgress 实现 Writer。
func (w *GitHubWriter) MarkInProgress(ctx context.Context, ref Ref, summary string) error {
	return w.upsert(ctx, ref, "in_progress", "", "变更单校验中", summary)
}

// Complete 实现 Writer。
func (w *GitHubWriter) Complete(ctx context.Context, ref Ref, outcome rules.Outcome) error {
	title := "变更单校验通过"
	if !outcome.OK {
		title = "变更单校验未通过"
	}
	return w.upsert(ctx, ref, "completed", outcome.Conclusion(), title, outcome.Render())
}

// upsert 幂等地创建/覆盖同名 check。
//
// ★ GitHub 的取用规则是"该 SHA + 该名称下**最新**的 check run"，
// 所以同名覆盖是正确的；每次新建会导致新旧结论并存、可能取到旧的。
func (w *GitHubWriter) upsert(ctx context.Context, ref Ref, status, conclusion, title, summary string) error {
	cl, err := w.factory.Client(InstallationIDFromContext(ctx))
	if err != nil {
		return err
	}

	output := &gogithub.CheckRunOutput{
		Title:   &title,
		Summary: &summary,
	}

	existing, _, err := cl.Checks.ListCheckRunsForRef(ctx, ref.Owner, ref.Repo, ref.SHA, nil)
	if err != nil {
		return fmt.Errorf("列出已有 check run: %w", err)
	}
	for _, r := range existing.CheckRuns {
		if r.GetName() != ref.Name {
			continue
		}
		opts := gogithub.UpdateCheckRunOptions{
			Name:   ref.Name,
			Status: &status,
			Output: output,
		}
		if conclusion != "" {
			opts.Conclusion = &conclusion
		}
		if status == "completed" {
			opts.CompletedAt = &gogithub.Timestamp{Time: time.Now()}
		}
		_, _, err = cl.Checks.UpdateCheckRun(ctx, ref.Owner, ref.Repo, r.GetID(), opts)
		return err
	}

	opts := gogithub.CreateCheckRunOptions{
		Name:    ref.Name,
		HeadSHA: ref.SHA,
		Status:  &status,
		Output:  output,
	}
	if conclusion != "" {
		opts.Conclusion = &conclusion
	}
	if status == "completed" {
		opts.CompletedAt = &gogithub.Timestamp{Time: time.Now()}
	}
	_, _, err = cl.Checks.CreateCheckRun(ctx, ref.Owner, ref.Repo, opts)
	return err
}

// installationIDKey 是 context 里携带 installation id 的键。
type installationIDKey struct{}

// WithInstallationID 把 installation id 放进 context。
func WithInstallationID(ctx context.Context, id int64) context.Context {
	return context.WithValue(ctx, installationIDKey{}, id)
}

// InstallationIDFromContext 取出 context 里的 installation id。
func InstallationIDFromContext(ctx context.Context) int64 {
	if v, ok := ctx.Value(installationIDKey{}).(int64); ok {
		return v
	}
	return 0
}
