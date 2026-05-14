# 多阶段构建 Dockerfile
# 适配平台 ConfigMap 配置

# 构建阶段
FROM golang:1.21-alpine AS builder

WORKDIR /app

# 复制依赖文件
COPY go.mod go.sum ./
RUN go mod download

# 复制源代码
COPY . .

# 构建应用
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o app .

# 运行阶段
FROM alpine:latest

# 安装 CA 证书和 OpenSSL（用于证书转换）
RUN apk --no-cache add ca-certificates openssl

WORKDIR /root/

# 从构建阶段复制二进制文件
COPY --from=builder /app/app .

# 配置文件和证书由 Kubernetes 挂载，无需 COPY
# /opt/config/server-conf.properties - ConfigMap 挂载
# /opt/keystore/* - Secret 挂载

# 暴露端口（默认 8443）
EXPOSE 8443

# 启动应用
CMD ["./app"]
