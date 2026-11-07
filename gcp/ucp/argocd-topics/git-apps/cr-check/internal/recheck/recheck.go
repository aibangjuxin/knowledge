// Package recheck 实现"定时重扫重评"。
//
// ★ 这是本项目**最容易被漏掉、但最重要**的一个组件。
//
// 原因：GitHub 的 required status check 是**按 head SHA 查已存在的结论**，
// 它不会在 merge 时刻重新执行你的规则。所以：
//
//	10:00  变更单有效 → 判定 success ✅
//	10:05  维护窗口关闭
//	10:30  有人点 Merge
//	       GitHub 看到 head SHA 上有个绿 check → 放行 ❌❌❌
//
// 而且 GitHub **不会自动重投失败的 webhook 投递**，事件丢了就永远丢了。
// 定时重扫同时解决这两个问题。
package recheck

import (
	"context"
	"log/slog"
	"sync"
	"time"

	"github.com/acme/cr-check/internal/rules"
)

// Entry 是被登记的 PR 快照。
type Entry struct {
	PR        rules.PRInfo `json:"pr"`
	UpdatedAt time.Time    `json:"updated_at"`
	// LastConclusion 记录上次判定结论（用于度量"结论翻转"）。
	LastConclusion string `json:"last_conclusion,omitempty"`
}

// Registry 保存受管分支上未合并的 PR 快照。
type Registry struct {
	mu      sync.RWMutex
	entries map[string]Entry
}

// NewRegistry 构造 registry。
func NewRegistry() *Registry {
	return &Registry{entries: map[string]Entry{}}
}

// Add 登记/更新一个 PR（保留上次的结论，用于度量翻转）。
func (r *Registry) Add(pr rules.PRInfo) {
	r.mu.Lock()
	defer r.mu.Unlock()
	e := Entry{PR: pr, UpdatedAt: time.Now()}
	if old, ok := r.entries[pr.Key()]; ok {
		e.LastConclusion = old.LastConclusion
	}
	r.entries[pr.Key()] = e
}

// Remove 移除一个 PR（合并/关闭后调用）。
func (r *Registry) Remove(key string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	delete(r.entries, key)
}

// Get 取一个 PR 快照。
func (r *Registry) Get(key string) (rules.PRInfo, bool) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	e, ok := r.entries[key]
	return e.PR, ok
}

// List 返回全部登记的 PR。
func (r *Registry) List() []Entry {
	r.mu.RLock()
	defer r.mu.RUnlock()
	out := make([]Entry, 0, len(r.entries))
	for _, e := range r.entries {
		out = append(out, e)
	}
	return out
}

// SetConclusion 记录某个 PR 的上次结论。
func (r *Registry) SetConclusion(key, conclusion string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if e, ok := r.entries[key]; ok {
		e.LastConclusion = conclusion
		r.entries[key] = e
	}
}

// Evaluator 是"重评一个 PR"的回调。
type Evaluator func(ctx context.Context, pr rules.PRInfo) (outcome rules.Outcome, err error)

// Scheduler 定期重扫。
type Scheduler struct {
	Registry *Registry
	Eval     Evaluator
	Interval time.Duration
	Logger   *slog.Logger

	// Flipped 记录结论翻转次数（★ 度量事件丢失率的关键指标）。
	flipped uint64
	mu      sync.Mutex

	// OnScanned / OnFlipped 是可选的指标回调。
	OnScanned func(n int)
	OnFlipped func()
}

// NewScheduler 构造调度器。
func NewScheduler(reg *Registry, eval Evaluator, interval time.Duration, logger *slog.Logger) *Scheduler {
	if interval <= 0 {
		interval = 5 * time.Minute
	}
	return &Scheduler{Registry: reg, Eval: eval, Interval: interval, Logger: logger}
}

// Flipped 返回结论翻转次数。
func (s *Scheduler) Flipped() uint64 {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.flipped
}

// Run 阻塞运行，直到 ctx 取消。
func (s *Scheduler) Run(ctx context.Context) {
	ticker := time.NewTicker(s.Interval)
	defer ticker.Stop()
	s.Logger.Info("定时重扫已启动", "interval", s.Interval)
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			s.RunOnce(ctx)
		}
	}
}

// RunOnce 立即执行一次重扫。
func (s *Scheduler) RunOnce(ctx context.Context) {
	entries := s.Registry.List()
	if len(entries) == 0 {
		return
	}
	s.Logger.Info("定时重扫开始", "prs", len(entries))
	if s.OnScanned != nil {
		s.OnScanned(len(entries))
	}
	for _, e := range entries {
		outcome, err := s.Eval(ctx, e.PR)
		if err != nil {
			s.Logger.Error("重评失败", "pr", e.PR.Key(), "err", err)
			continue
		}
		now := outcome.Conclusion()
		if e.LastConclusion != "" && e.LastConclusion != now {
			s.mu.Lock()
			s.flipped++
			s.mu.Unlock()
			if s.OnFlipped != nil {
				s.OnFlipped()
			}
			s.Logger.Warn("★ 重扫时结论发生翻转（说明有事件被漏掉了）",
				"pr", e.PR.Key(), "before", e.LastConclusion, "after", now)
		}
		s.Registry.SetConclusion(e.PR.Key(), now)
	}
}
