/**
 * Node.js 应用示例
 * 展示如何使用平台配置加载器
 */

const https = require('https');
const http = require('http');
const fs = require('fs');
const express = require('express');
const { loadPlatformConfig } = require('./platform-config-loader');

async function main() {
    try {
        // 加载平台配置
        const config = await loadPlatformConfig();
        console.log('Starting with config:', config.toString());

        // 创建 Express 应用
        const app = express();
        app.use(express.json());

        // 创建路由器
        const router = express.Router();

        // 健康检查端点
        router.get('/health', (req, res) => {
            res.json({
                status: 'ok',
                service: 'nodejs-app',
                timestamp: new Date().toISOString()
            });
        });

        // 就绪检查端点
        router.get('/ready', (req, res) => {
            res.json({
                ready: true,
                timestamp: new Date().toISOString()
            });
        });

        // 示例业务接口
        router.get('/hello', (req, res) => {
            res.json({
                message: 'Hello from Node.js',
                contextPath: config.contextPath,
                timestamp: new Date().toISOString()
            });
        });

        // 示例 POST 接口
        router.post('/data', (req, res) => {
            res.json({
                received: req.body,
                status: 'success',
                timestamp: new Date().toISOString()
            });
        });

        // 挂载路由到 Context Path
        app.use(config.contextPath, router);

        // 404 处理
        app.use((req, res) => {
            res.status(404).json({
                error: 'Not Found',
                path: req.path,
                contextPath: config.contextPath
            });
        });

        // 错误处理
        app.use((err, req, res, next) => {
            console.error('Error:', err);
            res.status(500).json({
                error: 'Internal Server Error',
                message: err.message
            });
        });

        // 根据配置选择 HTTP 或 HTTPS
        const port = parseInt(config.port);

        if (config.sslEnabled) {
            // HTTPS 服务器
            const options = {
                key: fs.readFileSync(config.keyPath),
                cert: fs.readFileSync(config.certPath),
                // TLS 配置
                minVersion: 'TLSv1.2',
                ciphers: [
                    'ECDHE-RSA-AES256-GCM-SHA384',
                    'ECDHE-RSA-AES128-GCM-SHA256',
                    'ECDHE-ECDSA-AES256-GCM-SHA384',
                    'ECDHE-ECDSA-AES128-GCM-SHA256'
                ].join(':')
            };

            const server = https.createServer(options, app);
            
            server.listen(port, () => {
                console.log(`HTTPS server listening on port ${port}`);
                console.log(`Context Path: ${config.contextPath}`);
                console.log(`Health check: https://localhost:${port}${config.contextPath}/health`);
            });

            // 优雅关闭
            process.on('SIGTERM', () => {
                console.log('SIGTERM received, closing server...');
                server.close(() => {
                    console.log('Server closed');
                    process.exit(0);
                });
            });
        } else {
            // HTTP 服务器
            const server = http.createServer(app);
            
            server.listen(port, () => {
                console.log(`HTTP server listening on port ${port}`);
                console.log(`Context Path: ${config.contextPath}`);
                console.log(`Health check: http://localhost:${port}${config.contextPath}/health`);
            });

            // 优雅关闭
            process.on('SIGTERM', () => {
                console.log('SIGTERM received, closing server...');
                server.close(() => {
                    console.log('Server closed');
                    process.exit(0);
                });
            });
        }

    } catch (error) {
        console.error('Failed to start server:', error.message);
        process.exit(1);
    }
}

// 启动应用
main();
