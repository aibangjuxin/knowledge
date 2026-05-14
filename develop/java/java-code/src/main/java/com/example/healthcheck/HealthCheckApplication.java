package com.example.healthcheck;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * 健康检查API应用程序主类
 * 
 * 这是一个简单的Spring Boot应用程序，提供健康检查功能
 * 
 * @author 学习者
 * @version 1.1.0
 */
@SpringBootApplication
public class HealthCheckApplication {

    public static void main(String[] args) {
        System.out.println("🚀 启动健康检查API服务...");
        SpringApplication.run(HealthCheckApplication.class, args);
        System.out.println("✅ 健康检查API服务启动成功！");
        System.out.println("📍 健康检查地址: http://localhost:8080/api_name_samples/v1.1.0/.well-known/health");
    }
}