多层构建
```dockerfile
# ================================
# Next.js 生产最优模板
# 最终镜像 130~160MB
# ================================

# 公共 base（只拉一次镜像，所有阶段共享）
FROM node:22-alpine AS base
RUN apk add --no-cache libc6-compat
# pnpm 只装一次，所有阶段都能用
RUN corepack enable && corepack prepare pnpm@latest --activate

# 1. 只安装生产依赖（缓存命中率极高）
FROM base AS deps
WORKDIR /app
COPY package.json pnpm-lock.yaml* ./
RUN pnpm install --frozen-lockfile --prod

# 2. 构建阶段
FROM base AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN pnpm build

# 3. 最终生产镜像
FROM base AS runner
WORKDIR /app

# 非 root 用户（安全）
RUN addgroup -S -g 1001 nodejs
RUN adduser -S -u 1001 nextjs

# 只复制独立运行所需的文件（Next.js 官方推荐的最小模式）
COPY --from=builder /app/next.config.mjs .* 
COPY --from=builder /app/package.json ./
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/public ./public

USER nextjs
EXPOSE 3000
ENV PORT=3000 NODE_ENV=production

CMD ["node", "server.js"]
```
Docker 镜像的优化，结合 AI ，给一个项目的 Dockerfile 优化了一下，最后只有 140M，真的非常舒服，总结几条：

* 使用 alpine 基础镜像，比普通的小太多了
* 先拷贝依赖文件，安装依赖，最大化利用 Docker 层缓存，改代码不重新装依赖
* 多阶段构建 base → builder → runner 三阶段，缓存依赖
* 最后只拷贝真正最后 build 的文件，这样各种开发依赖就不会在镜像中了，可以配合 dockerignore