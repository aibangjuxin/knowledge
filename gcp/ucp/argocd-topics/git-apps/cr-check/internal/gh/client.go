// Package gh 封装 GitHub App 的 installation client 构造。
//
// ★ 不要手写 JWT：installation token 1 小时过期，
// ghinstallation 会缓存并在过期前自动换取新 token。
package gh

import (
	"fmt"
	"net/http"
	"sync"

	"github.com/acme/cr-check/internal/config"
	"github.com/bradleyfalzon/ghinstallation/v2"
	gogithub "github.com/google/go-github/v88/github"
)

// Factory 按 installation_id 缓存 GitHub client。
type Factory struct {
	appID          int64
	privateKeyPath string
	apiURL         string

	mu      sync.Mutex
	clients map[int64]*gogithub.Client
}

// NewFactory 构造 client 工厂。
func NewFactory(cfg *config.GitHubConfig) *Factory {
	return &Factory{
		appID:          cfg.AppID,
		privateKeyPath: cfg.PrivateKeyPath,
		apiURL:         cfg.APIURL,
		clients:        map[int64]*gogithub.Client{},
	}
}

// Client 返回某个 installation 的 client（带缓存）。
func (f *Factory) Client(installationID int64) (*gogithub.Client, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if c, ok := f.clients[installationID]; ok {
		return c, nil
	}
	// ghinstallation 内部完成 JWT → installation token 的换取与 1h 过期续期。
	// ★ 第一个参数是底层 RoundTripper，传 nil 表示用 http.DefaultTransport。
	tr, err := ghinstallation.NewKeyFromFile(nil, f.appID, installationID, f.privateKeyPath)
	if err != nil {
		return nil, fmt.Errorf("构造 installation transport: %w", err)
	}
	c, err := gogithub.NewClient(gogithub.WithHTTPClient(&http.Client{Transport: tr}))
	if err != nil {
		return nil, fmt.Errorf("构造 GitHub client: %w", err)
	}
	if f.apiURL != "" {
		u := f.apiURL
		c, err = gogithub.NewClient(
			gogithub.WithHTTPClient(&http.Client{Transport: tr}),
			gogithub.WithURLs(&u, &u),
		)
		if err != nil {
			return nil, fmt.Errorf("构造 GitHub client（自定义 API 地址）: %w", err)
		}
	}
	f.clients[installationID] = c
	return c, nil
}

// InstallationIDFromEventHeader 尝试从 webhook payload 里取 installation id。
func InstallationIDFromEvent(raw []byte) int64 {
	// 极简扫描，避免为此引入完整反序列化
	const key = `"installation":{"id":`
	i := indexOf(raw, []byte(`"installation":{"id":`))
	if i < 0 {
		return 0
	}
	rest := raw[i+len(key):]
	j := 0
	for j < len(rest) && rest[j] >= '0' && rest[j] <= '9' {
		j++
	}
	var id int64
	for _, c := range rest[:j] {
		id = id*10 + int64(c-'0')
	}
	return id
}

func indexOf(haystack, needle []byte) int {
	n := len(needle)
	if n == 0 || len(haystack) < n {
		return -1
	}
	for i := 0; i+n <= len(haystack); i++ {
		match := true
		for j := 0; j < n; j++ {
			if haystack[i+j] != needle[j] {
				match = false
				break
			}
		}
		if match {
			return i
		}
	}
	return -1
}
