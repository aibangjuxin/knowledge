# 多阶段构建 Dockerfile
# 适配平台 ConfigMap 配置

# 构建阶段
FROM node:18-alpine AS builder

WORKDIR /app

# 复制依赖文件
COPY package*.json ./

# 安装依赖
RUN npm ci --only=production

# 复制源代码
COPY . .

# 运行阶段
FROM node:18-alpine

# 安装 OpenSSL（用于证书转换，如果需要）
RUN apk --no-cache add openssl ca-certificates

WORKDIR /app

# 从构建阶段复制文件
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/server.js ./
COPY --from=builder /app/platform-config-loader.js ./
COPY --from=builder /app/package.json ./

# 配置文件和证书由 Kubernetes 挂载，无需 COPY
# /opt/config/server-conf.properties - ConfigMap 挂载
# /opt/keystore/* - Secret 挂载

# 创建非 root 用户
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

# 切换到非 root 用户
USER nodejs

# 暴露端口（默认 8443）
EXPOSE 8443

# 健康检查
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
    CMD node -e "require('https').get('https://localhost:8443/health', {rejectUnauthorized: false}, (res) => process.exit(res.statusCode === 200 ? 0 : 1)).on('error', () => process.exit(1))"

# 启动应用
CMD ["node", "server.js"]
