package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLoadProperties(t *testing.T) {
	// 创建临时配置文件
	tmpDir := t.TempDir()
	configFile := filepath.Join(tmpDir, "test.properties")

	content := `# Test config
server.port=8443
server.ssl.enabled=true
server.servlet.context-path=/api/v1

# Comment line
empty.value=
`
	if err := os.WriteFile(configFile, []byte(content), 0644); err != nil {
		t.Fatal(err)
	}

	// 测试加载
	props, err := loadProperties(configFile)
	if err != nil {
		t.Fatalf("Failed to load properties: %v", err)
	}

	// 验证结果
	tests := []struct {
		key      string
		expected string
	}{
		{"server.port", "8443"},
		{"server.ssl.enabled", "true"},
		{"server.servlet.context-path", "/api/v1"},
		{"empty.value", ""},
	}

	for _, tt := range tests {
		if got := props[tt.key]; got != tt.expected {
			t.Errorf("props[%s] = %s, want %s", tt.key, got, tt.expected)
		}
	}
}

func TestExpandEnvVars(t *testing.T) {
	// 设置测试环境变量
	os.Setenv("TEST_API", "user-service")
	os.Setenv("TEST_VERSION", "1")
	defer os.Unsetenv("TEST_API")
	defer os.Unsetenv("TEST_VERSION")

	tests := []struct {
		input    string
		expected string
	}{
		{"/${TEST_API}/v${TEST_VERSION}", "/user-service/v1"},
		{"/api/v1", "/api/v1"},
		{"${TEST_API}", "user-service"},
		{"prefix-${TEST_API}-suffix", "prefix-user-service-suffix"},
		{"${NONEXISTENT}", "/"},
	}

	for _, tt := range tests {
		got := expandEnvVars(tt.input)
		if got != tt.expected {
			t.Errorf("expandEnvVars(%s) = %s, want %s", tt.input, got, tt.expected)
		}
	}
}

func TestLoadPlatformConfig(t *testing.T) {
	// 创建临时配置文件
	tmpDir := t.TempDir()
	configFile := filepath.Join(tmpDir, "server-conf.properties")

	content := `server.port=8443
server.ssl.enabled=true
server.ssl.key-store=/opt/keystore/test.p12
server.ssl.key-store-type=PKCS12
server.servlet.context-path=/${apiName}/v${minorVersion}
`
	if err := os.WriteFile(configFile, []byte(content), 0644); err != nil {
		t.Fatal(err)
	}

	// 设置环境变量
	os.Setenv("PLATFORM_CONFIG_PATH", configFile)
	os.Setenv("apiName", "test-service")
	os.Setenv("minorVersion", "2")
	os.Setenv("KEY_STORE_PWD", "test123")
	os.Setenv("TLS_CERT_PATH", "/tmp/test.crt")
	os.Setenv("TLS_KEY_PATH", "/tmp/test.key")
	defer func() {
		os.Unsetenv("PLATFORM_CONFIG_PATH")
		os.Unsetenv("apiName")
		os.Unsetenv("minorVersion")
		os.Unsetenv("KEY_STORE_PWD")
		os.Unsetenv("TLS_CERT_PATH")
		os.Unsetenv("TLS_KEY_PATH")
	}()

	// 加载配置
	cfg, err := LoadPlatformConfig()
	if err != nil {
		t.Fatalf("Failed to load config: %v", err)
	}

	// 验证配置
	if cfg.Port != "8443" {
		t.Errorf("Port = %s, want 8443", cfg.Port)
	}
	if !cfg.SSLEnabled {
		t.Error("SSLEnabled = false, want true")
	}
	if cfg.ContextPath != "/test-service/v2" {
		t.Errorf("ContextPath = %s, want /test-service/v2", cfg.ContextPath)
	}
	if cfg.KeyStorePwd != "test123" {
		t.Errorf("KeyStorePwd = %s, want test123", cfg.KeyStorePwd)
	}
	if cfg.TLSCertPath != "/tmp/test.crt" {
		t.Errorf("TLSCertPath = %s, want /tmp/test.crt", cfg.TLSCertPath)
	}
	if cfg.TLSKeyPath != "/tmp/test.key" {
		t.Errorf("TLSKeyPath = %s, want /tmp/test.key", cfg.TLSKeyPath)
	}
}

func TestValidate(t *testing.T) {
	// 创建临时证书文件
	tmpDir := t.TempDir()
	certFile := filepath.Join(tmpDir, "test.crt")
	keyFile := filepath.Join(tmpDir, "test.key")
	os.WriteFile(certFile, []byte("test cert"), 0644)
	os.WriteFile(keyFile, []byte("test key"), 0644)

	tests := []struct {
		name    string
		config  *PlatformConfig
		wantErr bool
	}{
		{
			name: "valid config",
			config: &PlatformConfig{
				Port:        "8443",
				SSLEnabled:  true,
				TLSCertPath: certFile,
				TLSKeyPath:  keyFile,
			},
			wantErr: false,
		},
		{
			name: "missing port",
			config: &PlatformConfig{
				Port:       "",
				SSLEnabled: false,
			},
			wantErr: true,
		},
		{
			name: "SSL enabled but missing cert",
			config: &PlatformConfig{
				Port:        "8443",
				SSLEnabled:  true,
				TLSCertPath: "",
				TLSKeyPath:  keyFile,
			},
			wantErr: true,
		},
		{
			name: "SSL enabled but cert file not found",
			config: &PlatformConfig{
				Port:        "8443",
				SSLEnabled:  true,
				TLSCertPath: "/nonexistent/cert.crt",
				TLSKeyPath:  keyFile,
			},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := tt.config.Validate()
			if (err != nil) != tt.wantErr {
				t.Errorf("Validate() error = %v, wantErr %v", err, tt.wantErr)
			}
		})
	}
}

func TestString(t *testing.T) {
	cfg := &PlatformConfig{
		Port:        "8443",
		SSLEnabled:  true,
		ContextPath: "/api/v1",
		TLSCertPath: "/opt/keystore/tls.crt",
		TLSKeyPath:  "/opt/keystore/tls.key",
		KeyStorePwd: "secret123",
	}

	str := cfg.String()

	// 验证密码已脱敏
	if contains(str, "secret123") {
		t.Error("String() should not contain actual password")
	}
	if !contains(str, "***") {
		t.Error("String() should contain masked password")
	}

	// 验证其他信息存在
	if !contains(str, "8443") {
		t.Error("String() should contain port")
	}
	if !contains(str, "/api/v1") {
		t.Error("String() should contain context path")
	}
}

func contains(s, substr string) bool {
	return len(s) >= len(substr) && (s == substr || len(s) > len(substr) && 
		(s[:len(substr)] == substr || s[len(s)-len(substr):] == substr || 
		len(s) > len(substr)+1 && findSubstring(s, substr)))
}

func findSubstring(s, substr string) bool {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}
