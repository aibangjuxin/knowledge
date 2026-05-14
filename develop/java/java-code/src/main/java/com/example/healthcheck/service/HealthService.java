package com.example.healthcheck.service;

import com.example.healthcheck.model.HealthResponse;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;

/**
 * 健康检查服务
 * 
 * 提供获取应用程序健康状态的业务逻辑
 */
@Service
public class HealthService {

    /**
     * 获取健康状态
     * 
     * @return 健康状态响应
     */
    public HealthResponse getHealthStatus() {
        HealthResponse response = new HealthResponse();
        response.setStatus("UP");
        response.setTimestamp(LocalDateTime.now());
        response.setVersion("1.1.0");
        response.setApplication("health-check-api");
        return response;
    }
}
