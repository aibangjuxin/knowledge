// Package audit 负责审计留痕。
//
// ★ 判定结论不能只存在 GitHub check 里 —— 半年后问"生产上这版是谁批的"，
// 没人答得上来。每一次判定都必须留一条可检索的记录。
package audit

import (
	"encoding/json"
	"io"
	"log/slog"
	"os"
	"sync"
	"time"
)

// Event 是一条审计记录。
type Event struct {
	Time        time.Time `json:"ts"`
	Kind        string    `json:"kind"`
	Repo        string    `json:"repo,omitempty"`
	PR          int       `json:"pr,omitempty"`
	HeadSHA     string    `json:"head_sha,omitempty"`
	BaseRef     string    `json:"base_ref,omitempty"`
	Env         string    `json:"env,omitempty"`
	CRNumber    string    `json:"cr_number,omitempty"`
	Conclusion  string    `json:"conclusion,omitempty"`
	SystemError bool      `json:"system_error,omitempty"`
	FailedRules []string  `json:"failed_rules,omitempty"`
	DeliveryID  string    `json:"delivery_id,omitempty"`
	Source      string    `json:"source,omitempty"` // webhook | recheck
	Detail      string    `json:"detail,omitempty"`
}

// Sink 把审计事件写到结构化日志与（可选的）文件。
type Sink struct {
	logger *slog.Logger
	mu     sync.Mutex
	file   *os.File
	recs   []Event
}

// NewSink 构造审计 sink。filePath 为空时只写日志。
func NewSink(logger *slog.Logger, filePath string) (*Sink, error) {
	s := &Sink{logger: logger}
	if filePath != "" {
		f, err := os.OpenFile(filePath, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o600)
		if err != nil {
			return nil, err
		}
		s.file = f
	}
	return s, nil
}

// Record 记录一条审计事件。
func (s *Sink) Record(e Event) {
	e.Time = time.Now()
	s.mu.Lock()
	s.recs = append(s.recs, e)
	if len(s.recs) > 500 {
		s.recs = s.recs[len(s.recs)-500:]
	}
	f := s.file
	s.mu.Unlock()

	s.logger.Info("audit",
		"kind", e.Kind, "repo", e.Repo, "pr", e.PR, "sha", e.HeadSHA,
		"cr", e.CRNumber, "conclusion", e.Conclusion,
		"failed_rules", e.FailedRules, "system_error", e.SystemError, "source", e.Source)

	if f != nil {
		if b, err := json.Marshal(e); err == nil {
			b = append(b, '\n')
			s.mu.Lock()
			_, _ = f.Write(b)
			s.mu.Unlock()
		}
	}
}

// Recent 返回最近的审计记录。
func (s *Sink) Recent(n int) []Event {
	s.mu.Lock()
	defer s.mu.Unlock()
	if n <= 0 || n > len(s.recs) {
		n = len(s.recs)
	}
	out := make([]Event, n)
	copy(out, s.recs[len(s.recs)-n:])
	return out
}

// Close 关闭审计文件。
func (s *Sink) Close() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.file != nil {
		return s.file.Close()
	}
	return nil
}

// Writer 返回一个把任意结构写成 JSON 行的 io.Writer（给 httputil.DumpRequest 之类用）。
func JSONLineWriter(w io.Writer) io.Writer { return w }
