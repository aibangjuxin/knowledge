package main

import (
	"crypto/tls"
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
	
	// 引入配置加载器
	// 实际使用时替换为你的项目路径，例如：
	// "your-project/pkg/config"
	"./config"
)

func main() {
	// 加载平台配置
	cfg, err := config.LoadPlatformConfig()
	if err != nil {
		log.Fatalf("Failed to load platform config: %v", err)
	}

	// 验证配置
	if err := cfg.Validate(); err != nil {
		log.Fatalf("Invalid config: %v", err)
	}

	// 打印配置信息（脱敏）
	log.Printf("Starting with config: %s", cfg.String())

	// 创建 Gin 路由
	r := gin.Default()

	// 使用 Group 实现 Context Path
	api := r.Group(cfg.ContextPath)
	{
		// 健康检查端点
		api.GET("/health", func(c *gin.Context) {
			c.JSON(http.StatusOK, gin.H{
				"status": "ok",
				"service": "golang-app",
			})
		})

		// 就绪检查端点
		api.GET("/ready", func(c *gin.Context) {
			c.JSON(http.StatusOK, gin.H{
				"ready": true,
			})
		})

		// 示例业务接口
		api.GET("/hello", func(c *gin.Context) {
			c.JSON(http.StatusOK, gin.H{
				"message": "Hello from Golang",
				"contextPath": cfg.ContextPath,
			})
		})

		// 示例 POST 接口
		api.POST("/data", func(c *gin.Context) {
			var data map[string]interface{}
			if err := c.BindJSON(&data); err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
				return
			}
			c.JSON(http.StatusOK, gin.H{
				"received": data,
				"status": "success",
			})
		})
	}

	// 构建监听地址
	addr := ":" + cfg.Port

	// 根据配置选择 HTTP 或 HTTPS
	if cfg.SSLEnabled {
		log.Printf("Starting HTTPS server on %s with context-path %s", addr, cfg.ContextPath)
		
		// 配置 TLS
		tlsConfig := &tls.Config{
			MinVersion: tls.VersionTLS12,
			CipherSuites: []uint16{
				tls.TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,
				tls.TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,
				tls.TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,
				tls.TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,
			},
		}

		server := &http.Server{
			Addr:      addr,
			Handler:   r,
			TLSConfig: tlsConfig,
		}

		if err := server.ListenAndServeTLS(cfg.TLSCertPath, cfg.TLSKeyPath); err != nil {
			log.Fatalf("Failed to start HTTPS server: %v", err)
		}
	} else {
		log.Printf("Starting HTTP server on %s with context-path %s", addr, cfg.ContextPath)
		if err := r.Run(addr); err != nil {
			log.Fatalf("Failed to start HTTP server: %v", err)
		}
	}
}
