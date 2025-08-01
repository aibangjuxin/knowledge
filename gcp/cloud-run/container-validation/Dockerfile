# 多阶段构建的Dockerfile示例
# 集成启动时校验功能

# 构建阶段
FROM node:18-alpine AS builder

WORKDIR /app

# 复制依赖文件
COPY package*.json ./
RUN npm ci --only=production

# 复制源代码
COPY . .

# 构建应用
RUN npm run build

# 运行阶段
FROM node:18-alpine AS runtime

# 安装必要的工具 (用于元数据访问)
RUN apk add --no-cache curl bash

# 创建应用用户
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nextjs -u 1001

WORKDIR /app

# 从构建阶段复制文件
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json ./package.json

# 复制校验脚本
COPY gcp/cloud-run/container-validation/startup-validator.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/startup-validator.sh

# 复制应用启动脚本
COPY gcp/cloud-run/container-validation/app-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/app-entrypoint.sh

# 构建时注入Git信息 (通过构建参数)
ARG GIT_BRANCH=unknown
ARG GIT_COMMIT=unknown
ARG BUILD_TIME=unknown
ARG BUILD_USER=unknown

# 将构建信息设置为环境变量
ENV GIT_BRANCH=${GIT_BRANCH}
ENV GIT_COMMIT=${GIT_COMMIT}
ENV BUILD_TIME=${BUILD_TIME}
ENV BUILD_USER=${BUILD_USER}

# 创建构建信息文件
RUN echo "GIT_BRANCH=${GIT_BRANCH}" > /app/.build-info && \
    echo "GIT_COMMIT=${GIT_COMMIT}" >> /app/.build-info && \
    echo "BUILD_TIME=${BUILD_TIME}" >> /app/.build-info && \
    echo "BUILD_USER=${BUILD_USER}" >> /app/.build-info

# 切换到非root用户
USER nextjs

# 暴露端口
EXPOSE 8080

# 健康检查
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# 使用自定义入口点 (先校验，再启动应用)
ENTRYPOINT ["/usr/local/bin/app-entrypoint.sh"]

# 默认命令
CMD ["node", "dist/index.js"]