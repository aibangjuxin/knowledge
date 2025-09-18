# GCP Cloud Run Java 超时问题调试指南

## 问题概述

当 GKE Pod 调用 Cloud Run 服务时出现 500 错误，同时客户端显示 `AsyncRequestTimeoutException`。这是一个典型的异步请求超时问题。

## 错误分析

### 客户端错误信息
```
org.springframework.web.context.request.async.AsyncRequestTimeoutException
```

这个异常表明：
- Spring Boot 应用使用了异步处理（DeferredResult 或 Callable）
- 异步请求在指定时间内没有完成
- 默认超时时间到达后触发了超时处理

### 可能的根本原因

1. **Cloud Run 服务响应慢**
   - 冷启动延迟
   - 业务逻辑处理时间过长
   - 数据库查询缓慢

2. **网络问题**
   - GKE 到 Cloud Run 的网络延迟
   - 网络丢包或不稳定

3. **超时配置不匹配**
   - 客户端超时设置过短
   - Cloud Run 服务超时设置

## 调试步骤

### 1. 检查 Cloud Run 服务端日志

```bash
# 查看 Cloud Run 服务日志
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=YOUR_SERVICE_NAME" --limit=50 --format="table(timestamp,severity,textPayload)"
```

**关键检查点：**
- 是否有对应的请求日志
- 请求处理时间
- 是否有 500 错误记录
- 冷启动