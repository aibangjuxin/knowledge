# ---- build ----
FROM golang:1.27-alpine AS build
WORKDIR /src

# 先只拷依赖描述文件 → 依赖层可复用缓存
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags '-s -w' -o /out/cr-check ./cmd/server

# ---- runtime ----
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/cr-check /cr-check
EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/cr-check"]
CMD ["-config", "/etc/cr-check/policy.yaml", "-mode", "real", "-addr", ":8080"]
