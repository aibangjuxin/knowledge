package config

import (
	"bufio"
	"fmt"
	"os"
	"strings"
)

// PlatformConfig 平台统一配置（简化版 - 用于独立 ConfigMap 方案）
type PlatformConfig struct {
	Port        string // 服务端口
	SSLEnabled  bool   // 是否启用 SSL
	CertPath    string // TLS 证书路径（PEM 格式）
	KeyPath     string // TLS 私钥路径（PEM 格式）
	ContextPath string // Context Path
}

// LoadPlatformConfig 从平台注入的 Golang ConfigMap 加载配置
// 默认读取 /opt/config/server-conf.properties
func LoadPlatformConfig() (*PlatformConfig, error) {
	configPath := os.Getenv("PLATFORM_CONFIG_PATH")
	if configPath == "" {
		configPath = "/opt/config/server-conf.properties"
	}

	props, err := loadProperties(configPath)
	if err != nil {
		return nil, fmt.Errorf("failed to load config: %w", err)
	}

	cfg := &PlatformConfig{
		Port:        getProperty(props, "server.port", "8443"),
		SSLEnabled:  getProperty(props, "server.ssl.enabled", "true") == "true",
		CertPath:    getProperty(props, "server.ssl.cert-path", "/opt/keystore/tls.crt"),
		KeyPath:     getProperty(props, "server.ssl.key-path", "/opt/keystore/tls.key"),
		ContextPath: getProperty(props, "server.context-path", "/"),
	}

	// 替换环境变量占位符
	cfg.ContextPath = expandEnvVars(cfg.ContextPath)

	return cfg, nil
}

// loadProperties 读取 Java properties 格式文件
func loadProperties(path string) (map[string]string, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	props := make(map[string]string)
	scanner := bufio.NewScanner(file)

	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())

		// 跳过注释和空行
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		// 解析 key=value
		parts := strings.SplitN(line, "=", 2)
		if len(parts) == 2 {
			key := strings.TrimSpace(parts[0])
			value := strings.TrimSpace(parts[1])
			props[key] = value
		}
	}

	if err := scanner.Err(); err != nil {
		return nil, err
	}

	return props, nil
}

// getProperty 获取配置值，支持默认值
func getProperty(props map[string]string, key, defaultValue string) string {
	if value, ok := props[key]; ok {
		return value
	}
	return defaultValue
}

// expandEnvVars 替换字符串中的环境变量占位符
// 支持 ${VAR_NAME} 格式
func expandEnvVars(s string) string {
	result := s
	
	// 查找所有 ${...} 占位符
	for {
		start := strings.Index(result, "${")
		if start == -1 {
			break
		}
		
		end := strings.Index(result[start:], "}")
		if end == -1 {
			break
		}
		end += start
		
		// 提取变量名
		varName := result[start+2 : end]
		varValue := os.Getenv(varName)
		
		// 替换占位符
		result = result[:start] + varValue + result[end+1:]
	}
	
	return result
}

// Validate 验证配置是否完整
func (c *PlatformConfig) Validate() error {
	if c.Port == "" {
		return fmt.Errorf("port is required")
	}

	if c.SSLEnabled {
		if c.CertPath == "" {
			return fmt.Errorf("cert path is required when SSL is enabled")
		}
		if c.KeyPath == "" {
			return fmt.Errorf("key path is required when SSL is enabled")
		}

		// 检查证书文件是否存在
		if _, err := os.Stat(c.CertPath); os.IsNotExist(err) {
			return fmt.Errorf("cert file not found: %s", c.CertPath)
		}
		if _, err := os.Stat(c.KeyPath); os.IsNotExist(err) {
			return fmt.Errorf("key file not found: %s", c.KeyPath)
		}
	}

	return nil
}

// String 返回配置的字符串表示
func (c *PlatformConfig) String() string {
	return fmt.Sprintf(
		"PlatformConfig{Port:%s, SSL:%v, ContextPath:%s, CertPath:%s, KeyPath:%s}",
		c.Port, c.SSLEnabled, c.ContextPath, c.CertPath, c.KeyPath,
	)
}
