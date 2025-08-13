package com.example.healthcheck.controller;

import com.example.healthcheck.model.HealthResponse;
import com.example.healthcheck.service.HealthService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.Map;

/**
 * 健康检查控制器
 * 
 * 提供健康检查API端点，返回应用程序的健康状态
 */
@RestController
@RequestMapping("/api_name_samples/v1.1.0/.well-known")
public class HealthController {

    @Autowired
    private HealthService healthService;

    /**
     * 健康检查端点
     * 
     * @return 健康状态响应
     */
    @GetMapping("/health")
    public ResponseEntity<HealthResponse> health() {
        System.out.println("📋 收到健康检查请求 - " + LocalDateTime.now());
        
        HealthResponse response = healthService.getHealthStatus();
        
        if (response.getStatus().equals("UP")) {
            return ResponseEntity.ok(response);
        } else {
            return ResponseEntity.status(503).body(response);
        }
    }

    /**
     * 详细健康检查端点
     * 
     * @return 详细的健康状态信息
     */
    @GetMapping("/health/detailed")
    public ResponseEntity<Map<String, Object>> detailedHealth() {
        System.out.println("📊 收到详细健康检查请求 - " + LocalDateTime.now());
        
        Map<String, Object> healthInfo = new HashMap<>();
        healthInfo.put("status", "UP");
        healthInfo.put("timestamp", LocalDateTime.now());
        healthInfo.put("version", "1.1.0");
        healthInfo.put("application", "health-check-api");
        
        // 系统信息
        Map<String, Object> systemInfo = new HashMap<>();
        systemInfo.put("javaVersion", System.getProperty("java.version"));
        systemInfo.put("osName", System.getProperty("os.name"));
        systemInfo.put("osVersion", System.getProperty("os.version"));
        systemInfo.put("availableProcessors", Runtime.getRuntime().availableProcessors());
        systemInfo.put("maxMemory", Runtime.getRuntime().maxMemory() / 1024 / 1024 + " MB");
        systemInfo.put("freeMemory", Runtime.getRuntime().freeMemory() / 1024 / 1024 + " MB");
        
        healthInfo.put("system", systemInfo);
        
        // 服务检查
        Map<String, String> services = new HashMap<>();
        services.put("database", "UP");  // 模拟数据库状态
        services.put("cache", "UP");     // 模拟缓存状态
        services.put("external-api", "UP"); // 模拟外部API状态
        
        healthInfo.put("services", services);
        
        return ResponseEntity.ok(healthInfo);
    }
}