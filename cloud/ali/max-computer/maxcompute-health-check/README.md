# MaxCompute Health Check API

这是一个用于检查 MaxCompute 连接状态的 Spring Boot 应用程序，主要用于安全扫描和连通性验证。

## 功能特性

- 提供 REST API 接口检查 MaxCompute 连接状态
- 支持环境变量和配置文件两种配置方式
- 包含详细的连接信息查询接口
- 集成 Spring Boot Actuator 健康检查
- 完整的错误处理和日志记录

## API 接口

### 1. 健康检查接口
```
GET /api/max_computer/health
```

**响应示例：**
```json
{
  "status": "SUCCESS",
  "message": "MaxCompute Connection Success",
  "timestamp": 1640995200000
}
```

### 2. 连接信息接口
```
GET /api/max_computer/info
```

**响应示例：**
```json
{
  "status": "SUCCESS",
  "data": {
    "project": "your-project",
    "endpoint": "http://service.cn-hangzhou.maxcompute.aliyun.com/api",
    "accessId": "your-access-id",
    "projectOwner": "owner-name",
    "sampleTableCount": 5
  },
  "timestamp": 1640995200000
}
```

## 配置方式

### 方式一：环境变量（推荐）
```bash
export ODPS_ACCESS_ID="your-access-id"
export ODPS_ACCESS_KEY="your-access-key"
export ODPS_PROJECT="your-project"
export ODPS_ENDPOINT="http://service.cn-hangzhou.maxcompute.aliyun.com/api"
```

### 方式二：修改 application.yml
```yaml
maxcompute:
  access:
    id: your-access-id
    key: your-access-key
  project: your-project
  endpoint: http://service.cn-hangzhou.maxcompute.aliyun.com/api
```

## 运行方式

### 1. 本地开发运行
```bash
# 设置环境变量
export ODPS_ACCESS_ID="your-access-id"
export ODPS_ACCESS_KEY="your-access-key"
export ODPS_PROJECT="your-project"
export ODPS_ENDPOINT="http://service.cn-hangzhou.maxcompute.aliyun.com/api"

# 运行应用
mvn spring-boot:run
```

### 2. 打包部署
```bash
# 编译打包
mvn clean package

# 运行 JAR 包
java -jar target/maxcompute-health-check-1.0.0.jar
```

### 3. Docker 部署
```bash
# 构建镜像
docker build -t maxcompute-health-check .

# 运行容器
docker run -d \
  -p 8080:8080 \
  -e ODPS_ACCESS_ID="your-access-id" \
  -e ODPS_ACCESS_KEY="your-access-key" \
  -e ODPS_PROJECT="your-project" \
  -e ODPS_ENDPOINT="http://service.cn-hangzhou.maxcompute.aliyun.com/api" \
  maxcompute-health-check
```

## 测试验证

启动应用后，可以通过以下方式测试：

```bash
# 健康检查
curl http://localhost:8080/api/max_computer/health

# 连接信息
curl http://localhost:8080/api/max_computer/info

# Spring Boot Actuator 健康检查
curl http://localhost:8080/actuator/health
```

## 安全注意事项

1. **不要在代码中硬编码密钥**：使用环境变量或安全的密钥管理系统
2. **网络访问**：确保服务器能访问 `*.maxcompute.aliyun.com`
3. **权限控制**：MaxCompute 账号只需要最小必要权限（读取权限即可）
4. **超时设置**：默认30秒超时，可根据需要调整

## 故障排查

1. **连接失败**：检查网络连通性和防火墙设置
2. **认证失败**：验证 AccessId 和 AccessKey 是否正确
3. **项目不存在**：确认项目名称和权限
4. **超时问题**：调整 `maxcompute.timeout` 配置

## 项目结构

```
src/
├── main/
│   ├── java/
│   │   └── com/company/maxcompute/
│   │       ├── MaxComputeHealthCheckApplication.java
│   │       ├── controller/
│   │       │   └── MaxComputeHealthController.java
│   │       └── service/
│   │           └── MaxComputeHealthService.java
│   └── resources/
│       └── application.yml
└── test/
    └── java/
        └── com/company/maxcompute/
            └── MaxComputeHealthCheckApplicationTests.java
```