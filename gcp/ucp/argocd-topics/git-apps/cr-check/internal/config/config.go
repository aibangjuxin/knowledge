// Package config 负责加载与校验 CR Check 的策略配置（policy.yaml）。
//
// 配置分两层：
//   - 规则数据（阈值 / 名单 / 映射表 / 窗口）→ 本文件，改配置走 PR + 部署，分钟级生效
//   - 判定逻辑（怎么算合规）→ rules 包，改逻辑要走 CI + 发版
package config

import (
	"fmt"
	"os"
	"regexp"
	"strconv"
	"strings"
	"time"

	"sigs.k8s.io/yaml"
)

// Config 是 CR Check 的完整策略配置。
type Config struct {
	// CheckName 是 check run 的名字。
	// ★ 必须与 GitHub 分支保护里 required status check 的名字**逐字符一致**（含斜杠）。
	CheckName string `json:"checkName"`

	// Timezone 是全局时区（IANA 名，如 Asia/Shanghai）。
	// ★ 不要用 UTC 偏移硬编码。
	Timezone string `json:"timezone"`

	// ManagedBranches 是受管 basebranch 集合（R0b 过滤）。
	// 只有 base 命中这里面的分支，PR 才会进入判定。
	ManagedBranches []string `json:"managedBranches"`

	// BranchEnvMap 把 base 分支映射到环境（R5 目标环境匹配）。
	BranchEnvMap map[string]string `json:"branchEnvMap"`

	CR         CRConfig         `json:"cr"`
	Windows    []WindowConfig   `json:"windows"`
	Webhook    WebhookConfig    `json:"webhook"`
	GitHub     GitHubConfig     `json:"github"`
	CRPlatform CRPlatformConfig `json:"crPlatform"`
	Server     ServerConfig     `json:"server"`
	Mock       MockConfig       `json:"mock"`
}

// CRConfig 是变更单（CR）相关的规则数据。
type CRConfig struct {
	// AllowedExecutableStatuses 是"允许作为部署依据"的状态集合（规范化后的状态名）。
	// ★ 白名单之外的状态一律 fail-closed（未知状态 = 不通过）。
	AllowedExecutableStatuses []string `json:"allowedExecutableStatuses"`

	// StatusAliases 把 CR 平台的状态字符串映射到规范化状态。
	// key 是规范化状态名，value 是平台里可能出现的写法（大小写不敏感）。
	// 例：implement: [Implement, 实施中, 可执行]
	StatusAliases map[string][]string `json:"statusAliases"`

	// MinApprovals 是最少审批人数（R4）。
	MinApprovals int `json:"minApprovals"`

	// ForbidSelfApproval 表示提单人不能审批自己的 CR（R4）。
	ForbidSelfApproval bool `json:"forbidSelfApproval"`

	// AllowedApprovers 是审批人白名单。
	// ⚠️ 生产上这里应该来自 CR 平台的组信息；本地版本用静态名单近似。
	AllowedApprovers []string `json:"allowedApprovers"`

	// LabelPrefix 是 CR label 的前缀，默认 "cr/"。
	LabelPrefix string `json:"labelPrefix"`

	// LabelPattern 是 CR label 的正则，默认 "^cr/[0-9]+$"。
	LabelPattern string `json:"labelPattern"`

	// BodyMarker 是 PR body / commit trailer 里的字段名，默认 "Change-Request:"。
	BodyMarker string `json:"bodyMarker"`
}

// WindowConfig 是一个按周重复的维护窗口（Maintenance Window）。
type WindowConfig struct {
	// Env 是这个窗口适用的环境（对应 BranchEnvMap 的值）。
	Env string `json:"env"`
	// Days 是生效的星期（Mon/Tue/...）。
	Days []string `json:"days"`
	// Start / End 是 "HH:MM"，左闭右开 [start, end)。
	// ★ Start > End 表示跨零点（例如 22:00 → 02:00）。
	Start string `json:"start"`
	End   string `json:"end"`
	// TZ 是时区（IANA 名）；为空则用全局 Timezone。
	TZ string `json:"tz"`
}

// WebhookConfig 是 webhook 接收端配置。
type WebhookConfig struct {
	// Secret 用于校验 X-Hub-Signature-256。生产必须有；本地调试可为空。
	Secret string `json:"secret"`
	// Events 是订阅的事件白名单。
	Events []string `json:"events"`
	// MaxBodyBytes 是请求体上限（防内存打爆）。
	MaxBodyBytes int64 `json:"maxBodyBytes"`
}

// GitHubConfig 是 GitHub App 侧的凭据与地址。
type GitHubConfig struct {
	AppID          int64  `json:"appId"`
	InstallationID int64  `json:"installationId"`
	PrivateKeyPath string `json:"privateKeyPath"`
	// APIURL 是 GitHub API 地址，GitHub Enterprise 用 https://<host>/api/v3。
	APIURL string `json:"apiURL"`
}

// CRPlatformConfig 是内部 CR 管理平台的访问配置。
type CRPlatformConfig struct {
	BaseURL string `json:"baseURL"`
	Token   string `json:"token"`
	// Path 是查询单个变更单的路径模板，{number} 会被替换。
	Path string `json:"path"`
	// TimeoutSeconds 是单次调用超时。
	TimeoutSeconds int `json:"timeoutSeconds"`
}

// ServerConfig 是服务端自身的配置。
type ServerConfig struct {
	Addr string `json:"addr"`
	// SyncEval 为 true 时在 webhook handler 内同步完成判定（本地调试用）；
	// 生产必须 false —— 先 ACK 再异步，避免超过 GitHub 的 10 秒投递预算。
	SyncEval bool `json:"syncEval"`
	// Workers 是异步判定的并发 worker 数。
	Workers int `json:"workers"`
	// RecheckIntervalSeconds 是定时重扫的间隔（秒）。
	// ★ 这是兜底机制：GitHub 不会自动重投失败的投递，
	// 而且 required status check 不会在 merge 时刻重新判定。
	RecheckIntervalSeconds int `json:"recheckIntervalSeconds"`
}

// MockConfig 是本地 mock 数据（仅在 mock 模式生效）。
type MockConfig struct {
	Enabled bool     `json:"enabled"`
	CRs     []MockCR `json:"crs"`
}

// MockCR 是一条 mock 变更单。
type MockCR struct {
	Number    string   `json:"number"`
	Status    string   `json:"status"`
	Requester string   `json:"requester"`
	Approvers []string `json:"approvers"`
	TargetEnv string   `json:"targetEnv"`
	ValidFrom string   `json:"validFrom"`
	ValidTo   string   `json:"validTo"`
	URL       string   `json:"url"`
	// Error 非空时模拟"平台调用失败"（系统异常 → 必须 fail-closed）。
	Error string `json:"error"`
}

// Load 从 YAML 文件加载配置，应用环境变量覆盖，然后校验。
func Load(path string) (*Config, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("读取配置 %s: %w", path, err)
	}
	var c Config
	if err := yaml.Unmarshal(b, &c); err != nil {
		return nil, fmt.Errorf("解析配置 %s: %w", path, err)
	}
	c.applyEnv()
	if err := c.Validate(); err != nil {
		return nil, err
	}
	return &c, nil
}

// applyEnv 用环境变量覆盖敏感项 —— 敏感值一律不进 Git。
func (c *Config) applyEnv() {
	set := func(key string, dst *string) {
		if v := os.Getenv(key); v != "" {
			*dst = v
		}
	}
	set("WEBHOOK_SECRET", &c.Webhook.Secret)
	set("GITHUB_APP_PRIVATE_KEY_PATH", &c.GitHub.PrivateKeyPath)
	set("GITHUB_API_URL", &c.GitHub.APIURL)
	set("CR_PLATFORM_URL", &c.CRPlatform.BaseURL)
	set("CR_PLATFORM_TOKEN", &c.CRPlatform.Token)
	set("CHECK_NAME", &c.CheckName)

	if v := os.Getenv("GITHUB_APP_ID"); v != "" {
		if n, err := strconv.ParseInt(v, 10, 64); err == nil {
			c.GitHub.AppID = n
		}
	}
	if v := os.Getenv("GITHUB_APP_INSTALLATION_ID"); v != "" {
		if n, err := strconv.ParseInt(v, 10, 64); err == nil {
			c.GitHub.InstallationID = n
		}
	}
	if v := os.Getenv("ADDR"); v != "" {
		c.Server.Addr = v
	}
}

// Validate 检查配置是否自洽。
func (c *Config) Validate() error {
	if c.CheckName == "" {
		return fmt.Errorf("checkName 不能为空（必须与分支保护里的 required check 名一致）")
	}
	if c.Timezone == "" {
		c.Timezone = "UTC"
	}
	if _, err := time.LoadLocation(c.Timezone); err != nil {
		return fmt.Errorf("timezone %q 无效: %w", c.Timezone, err)
	}
	if len(c.ManagedBranches) == 0 {
		return fmt.Errorf("managedBranches 不能为空（否则没有任何 PR 会进入判定）")
	}
	if c.BranchEnvMap == nil {
		c.BranchEnvMap = map[string]string{}
	}
	if len(c.CR.AllowedExecutableStatuses) == 0 {
		return fmt.Errorf("cr.allowedExecutableStatuses 不能为空")
	}
	if c.CR.LabelPrefix == "" {
		c.CR.LabelPrefix = "cr/"
	}
	if c.CR.LabelPattern == "" {
		c.CR.LabelPattern = "^" + regexp.QuoteMeta(c.CR.LabelPrefix) + `[0-9A-Za-z._-]+$`
	}
	if _, err := regexp.Compile(c.CR.LabelPattern); err != nil {
		return fmt.Errorf("cr.labelPattern 无效: %w", err)
	}
	if c.CR.BodyMarker == "" {
		c.CR.BodyMarker = "Change-Request:"
	}
	if c.Webhook.MaxBodyBytes <= 0 {
		c.Webhook.MaxBodyBytes = 2 << 20 // 2MB
	}
	if len(c.Webhook.Events) == 0 {
		c.Webhook.Events = []string{"pull_request", "pull_request_review", "check_run", "merge_group", "installation"}
	}
	if c.CRPlatform.Path == "" {
		c.CRPlatform.Path = "/api/change-requests/{number}"
	}
	if c.CRPlatform.TimeoutSeconds <= 0 {
		c.CRPlatform.TimeoutSeconds = 5
	}
	if c.Server.Addr == "" {
		c.Server.Addr = ":8080"
	}
	if c.Server.Workers <= 0 {
		c.Server.Workers = 4
	}
	if c.Server.RecheckIntervalSeconds <= 0 {
		c.Server.RecheckIntervalSeconds = 300
	}
	for i, w := range c.Windows {
		if _, err := parseHM(w.Start); err != nil {
			return fmt.Errorf("windows[%d].start 无效: %w", i, err)
		}
		if _, err := parseHM(w.End); err != nil {
			return fmt.Errorf("windows[%d].end 无效: %w", i, err)
		}
	}
	return nil
}

// IsManagedBranch 判断一个 base 分支是否受管控（R0b）。
func (c *Config) IsManagedBranch(ref string) bool {
	for _, b := range c.ManagedBranches {
		if b == ref {
			return true
		}
	}
	return false
}

// EnvForBranch 返回 base 分支对应的环境（R5）。未映射时返回空串。
func (c *Config) EnvForBranch(ref string) string {
	if env, ok := c.BranchEnvMap[ref]; ok {
		return env
	}
	return ""
}

// WindowForEnv 返回某个环境的维护窗口配置。
func (c *Config) WindowForEnv(env string) (*WindowConfig, bool) {
	for i := range c.Windows {
		if c.Windows[i].Env == env {
			return &c.Windows[i], true
		}
	}
	return nil, false
}

// IsExecutableStatus 判断规范化状态是否在"可执行"白名单里。
func (c *Config) IsExecutableStatus(s string) bool {
	for _, a := range c.CR.AllowedExecutableStatuses {
		if strings.EqualFold(a, s) {
			return true
		}
	}
	return false
}

// WebhookSecretBytes 返回 webhook secret（可能为空 = 不验签，仅限本地调试）。
func (c *Config) WebhookSecretBytes() []byte {
	return []byte(c.Webhook.Secret)
}

// HasGitHubCredentials 判断 GitHub 侧凭据是否齐全。
func (c *Config) HasGitHubCredentials() bool {
	return c.GitHub.AppID != 0 && c.GitHub.InstallationID != 0 && c.GitHub.PrivateKeyPath != ""
}

// HasCRPlatform 判断 CR 平台是否配置了地址。
func (c *Config) HasCRPlatform() bool {
	return c.CRPlatform.BaseURL != ""
}

// Redacted 返回一份脱敏后的配置副本（用于 /internal/policy 展示）。
func (c *Config) Redacted() map[string]any {
	return map[string]any{
		"checkName":        c.CheckName,
		"timezone":         c.Timezone,
		"managedBranches":  c.ManagedBranches,
		"branchEnvMap":     c.BranchEnvMap,
		"allowedStatuses":  c.CR.AllowedExecutableStatuses,
		"minApprovals":     c.CR.MinApprovals,
		"labelPattern":     c.CR.LabelPattern,
		"bodyMarker":       c.CR.BodyMarker,
		"webhookSecretSet": c.Webhook.Secret != "",
		"githubConfigured": c.HasGitHubCredentials(),
		"crPlatformSet":    c.HasCRPlatform(),
	}
}

// parseHM 解析 "HH:MM" → 当天零点起的分钟数。
func parseHM(s string) (int, error) {
	parts := strings.Split(strings.TrimSpace(s), ":")
	if len(parts) != 2 {
		return 0, fmt.Errorf("期望 HH:MM，得到 %q", s)
	}
	h, err := strconv.Atoi(parts[0])
	if err != nil || h < 0 || h > 24 {
		return 0, fmt.Errorf("小时非法: %q", s)
	}
	m, err := strconv.Atoi(parts[1])
	if err != nil || m < 0 || m > 59 {
		return 0, fmt.Errorf("分钟非法: %q", s)
	}
	return h*60 + m, nil
}

// ParseHM 是 parseHM 的导出版本，供 rules 包解析窗口使用。
func ParseHM(s string) (int, error) { return parseHM(s) }
