// Package crplatform 是内部 CR 管理平台的客户端与领域模型。
//
// ★ 职责边界：rules 包只认这里的规范化模型（ChangeRequest），
// 不认平台的原始响应格式 —— 平台改字段时只需要改这个包。
package crplatform

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"sync"
	"time"
)

// Status 是规范化后的变更单状态。
type Status string

const (
	StatusUnknown   Status = "unknown"
	StatusDraft     Status = "draft"
	StatusReviewing Status = "reviewing"
	StatusApproved  Status = "approved"
	StatusImplement Status = "implement"
	StatusRejected  Status = "rejected"
	StatusCancelled Status = "cancelled"
	StatusExpired   Status = "expired"
)

// Approval 是一条审批记录。
type Approval struct {
	Approver  string    `json:"approver"`
	DecidedAt time.Time `json:"decidedAt"`
	Decision  string    `json:"decision"`
}

// ChangeRequest 是 CR 管理平台的规范化视图。
type ChangeRequest struct {
	Number    string     `json:"number"`
	Status    Status     `json:"status"`
	Requester string     `json:"requester"`
	Approvers []Approval `json:"approvers"`
	TargetEnv string     `json:"targetEnv"`
	ValidFrom time.Time  `json:"validFrom"`
	ValidTo   time.Time  `json:"validTo"`
	Artifacts []string   `json:"artifacts"`
	URL       string     `json:"url"`
}

// IsExecutable 判断状态是否"可执行"。
// 注意：真正的判定用配置里的白名单（见 config.IsExecutableStatus），
// 这里只是方便日志与渲染。
func (c *ChangeRequest) IsExecutable() bool {
	return c.Status == StatusApproved || c.Status == StatusImplement
}

// ApproverNames 返回所有"同意"的审批人。
func (c *ChangeRequest) ApproverNames() []string {
	var out []string
	for _, a := range c.Approvers {
		if strings.EqualFold(a.Decision, "approve") {
			out = append(out, a.Approver)
		}
	}
	return out
}

// Client 是查询变更单的接口。
//
// ★ 返回值语义（整个设计的关键）：
//
//	(nil, nil) → 平台确认"不存在" → 业务不通过 → check = failure，理由明确
//	(err)      → 平台超时 / 5xx / 解析失败 → 系统异常 → check = failure（不得写 success）
type Client interface {
	Get(ctx context.Context, number string) (*ChangeRequest, error)
}

// NormalizeStatus 把平台返回的状态字符串映射成规范化状态。
// ★ 映射表之外的一切 → StatusUnknown（fail-closed：未知状态 = 不通过）。
func NormalizeStatus(raw string, aliases map[string][]string) Status {
	s := strings.TrimSpace(strings.ToLower(raw))
	if s == "" {
		return StatusUnknown
	}
	for canonical, names := range aliases {
		if strings.EqualFold(canonical, s) {
			return Status(canonical)
		}
		for _, n := range names {
			if strings.EqualFold(strings.TrimSpace(n), s) {
				return Status(canonical)
			}
		}
	}
	// 兜底：规范状态名本身（draft/approved/...）总是被认识
	switch Status(s) {
	case StatusDraft, StatusReviewing, StatusApproved, StatusImplement,
		StatusRejected, StatusCancelled, StatusExpired:
		return Status(s)
	}
	return StatusUnknown
}

// ─────────────────────────────────────────────────────────────
// HTTP 客户端（对接真实的 CR 管理平台）
// ─────────────────────────────────────────────────────────────

// HTTPClient 通过 HTTP 调用 CR 管理平台。
type HTTPClient struct {
	baseURL string
	token   string
	path    string
	aliases map[string][]string
	http    *http.Client
}

// NewHTTPClient 创建平台客户端。
func NewHTTPClient(baseURL, token, path string, timeout time.Duration, aliases map[string][]string) *HTTPClient {
	return &HTTPClient{
		baseURL: strings.TrimRight(baseURL, "/"),
		token:   token,
		path:    path,
		aliases: aliases,
		http:    &http.Client{Timeout: timeout},
	}
}

// platformResponse 是平台返回的原始结构。
type platformResponse struct {
	Number    string `json:"number"`
	Status    string `json:"status"`
	Requester string `json:"requester"`
	Approvers []struct {
		Approver  string `json:"approver"`
		DecidedAt string `json:"decidedAt"`
		Decision  string `json:"decision"`
	} `json:"approvers"`
	TargetEnv string   `json:"targetEnv"`
	ValidFrom string   `json:"validFrom"`
	ValidTo   string   `json:"validTo"`
	Artifacts []string `json:"artifacts"`
	URL       string   `json:"url"`
}

// Get 查询一个变更单。
func (c *HTTPClient) Get(ctx context.Context, number string) (*ChangeRequest, error) {
	url := c.baseURL + strings.ReplaceAll(c.path, "{number}", number)

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, fmt.Errorf("构造请求: %w", err)
	}
	if c.token != "" {
		req.Header.Set("Authorization", "Bearer "+c.token)
	}
	req.Header.Set("Accept", "application/json")

	resp, err := c.http.Do(req)
	if err != nil {
		return nil, fmt.Errorf("调用 CR 平台失败: %w", err)
	}
	defer func() { _ = resp.Body.Close() }()

	switch {
	case resp.StatusCode == http.StatusNotFound:
		// 业务语义：变更单不存在
		return nil, nil
	case resp.StatusCode >= 500:
		return nil, fmt.Errorf("CR 平台返回 %d", resp.StatusCode)
	case resp.StatusCode >= 400:
		return nil, fmt.Errorf("CR 平台返回 %d", resp.StatusCode)
	}

	var raw platformResponse
	if err := json.NewDecoder(resp.Body).Decode(&raw); err != nil {
		return nil, fmt.Errorf("解析 CR 平台响应: %w", err)
	}
	if raw.Number == "" {
		raw.Number = number
	}
	return raw.toModel(c.aliases), nil
}

// toModel 把平台原始结构转成规范化模型。
func (r platformResponse) toModel(aliases map[string][]string) *ChangeRequest {
	cr := &ChangeRequest{
		Number:    r.Number,
		Status:    NormalizeStatus(r.Status, aliases),
		Requester: r.Requester,
		TargetEnv: r.TargetEnv,
		Artifacts: r.Artifacts,
		URL:       r.URL,
	}
	for _, a := range r.Approvers {
		t, _ := time.Parse(time.RFC3339, a.DecidedAt)
		cr.Approvers = append(cr.Approvers, Approval{
			Approver:  a.Approver,
			DecidedAt: t,
			Decision:  a.Decision,
		})
	}
	cr.ValidFrom, _ = time.Parse(time.RFC3339, r.ValidFrom)
	cr.ValidTo, _ = time.Parse(time.RFC3339, r.ValidTo)
	return cr
}

// ─────────────────────────────────────────────────────────────
// Mock 客户端（本地开发 / 单测用）
// ─────────────────────────────────────────────────────────────

// MockClient 是内存里的假 CR 平台。
type MockClient struct {
	mu      sync.RWMutex
	items   map[string]*ChangeRequest
	errs    map[string]error
	aliases map[string][]string
}

// NewMockClient 用配置里的 mock 数据构造。
func NewMockClient(aliases map[string][]string) *MockClient {
	return &MockClient{
		items:   map[string]*ChangeRequest{},
		errs:    map[string]error{},
		aliases: aliases,
	}
}

// Add 放入一条变更单。
func (m *MockClient) Add(cr *ChangeRequest) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.items[cr.Number] = cr
}

// AddError 让某个编号的查询返回错误（模拟平台故障）。
func (m *MockClient) AddError(number string, err error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.errs[number] = err
}

// Get 实现 Client。
func (m *MockClient) Get(_ context.Context, number string) (*ChangeRequest, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	if err, ok := m.errs[number]; ok {
		return nil, err
	}
	cr, ok := m.items[number]
	if !ok {
		return nil, nil // 不存在 = 业务不通过
	}
	cp := *cr
	return &cp, nil
}

// List 返回全部 mock 变更单。
func (m *MockClient) List() []*ChangeRequest {
	m.mu.RLock()
	defer m.mu.RUnlock()
	out := make([]*ChangeRequest, 0, len(m.items))
	for _, cr := range m.items {
		cp := *cr
		out = append(out, &cp)
	}
	return out
}

// Handler 把 mock 平台暴露成一个 HTTP 接口，方便用 curl 直接观察。
func (m *MockClient) Handler(prefix string) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc(prefix, func(w http.ResponseWriter, r *http.Request) {
		number := strings.TrimPrefix(r.URL.Path, prefix)
		number = strings.Trim(number, "/")
		if number == "" {
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(map[string]any{"items": m.List()})
			return
		}
		cr, err := m.Get(r.Context(), number)
		w.Header().Set("Content-Type", "application/json")
		if err != nil {
			w.WriteHeader(http.StatusInternalServerError)
			_ = json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
			return
		}
		if cr == nil {
			w.WriteHeader(http.StatusNotFound)
			_ = json.NewEncoder(w).Encode(map[string]string{"error": "变更单不存在", "number": number})
			return
		}
		_ = json.NewEncoder(w).Encode(cr)
	})
	return mux
}
