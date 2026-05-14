package com.company.maxcompute.service;

import com.aliyun.odps.*;
import com.aliyun.odps.account.AliyunAccount;
import com.aliyun.odps.task.SQLTask;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.util.HashMap;
import java.util.Map;

@Service
public class MaxComputeHealthService {

    private static final Logger logger = LoggerFactory.getLogger(MaxComputeHealthService.class);

    @Value("${maxcompute.access.id:}")
    private String accessId;

    @Value("${maxcompute.access.key:}")
    private String accessKey;

    @Value("${maxcompute.project:}")
    private String project;

    @Value("${maxcompute.endpoint:}")
    private String endpoint;

    @Value("${maxcompute.timeout:30000}")
    private long timeout;

    public boolean checkConnection() {
        try {
            // 获取环境变量（优先级高于配置文件）
            String actualAccessId = getEnvOrConfig("ODPS_ACCESS_ID", accessId);
            String actualAccessKey = getEnvOrConfig("ODPS_ACCESS_KEY", accessKey);
            String actualProject = getEnvOrConfig("ODPS_PROJECT", project);
            String actualEndpoint = getEnvOrConfig("ODPS_ENDPOINT", endpoint);

            if (actualAccessId.isEmpty() || actualAccessKey.isEmpty() || 
                actualProject.isEmpty() || actualEndpoint.isEmpty()) {
                logger.error("MaxCompute configuration is incomplete");
                return false;
            }

            logger.info("Checking MaxCompute connection to project: {}", actualProject);

            // 创建 MaxCompute 连接
            Account account = new AliyunAccount(actualAccessId, actualAccessKey);
            Odps odps = new Odps(account);
            odps.setEndpoint(actualEndpoint);
            odps.setDefaultProject(actualProject);

            // 执行简单查询来验证连接
            String sql = "SELECT 1 AS test_connection";
            Instance instance = SQLTask.run(odps, sql);
            
            // 等待任务完成，设置超时时间
            instance.waitForSuccess(timeout);
            
            logger.info("MaxCompute connection test successful");
            return true;

        } catch (Exception e) {
            logger.error("MaxCompute connection test failed: {}", e.getMessage(), e);
            return false;
        }
    }

    public Map<String, Object> getConnectionInfo() throws Exception {
        Map<String, Object> info = new HashMap<>();
        
        String actualAccessId = getEnvOrConfig("ODPS_ACCESS_ID", accessId);
        String actualProject = getEnvOrConfig("ODPS_PROJECT", project);
        String actualEndpoint = getEnvOrConfig("ODPS_ENDPOINT", endpoint);

        if (actualAccessId.isEmpty() || actualProject.isEmpty() || actualEndpoint.isEmpty()) {
            throw new RuntimeException("MaxCompute configuration is incomplete");
        }

        // 创建连接并获取项目信息
        Account account = new AliyunAccount(actualAccessId, getEnvOrConfig("ODPS_ACCESS_KEY", accessKey));
        Odps odps = new Odps(account);
        odps.setEndpoint(actualEndpoint);
        odps.setDefaultProject(actualProject);

        // 获取项目信息
        Project projectInfo = odps.projects().get(actualProject);
        
        info.put("project", actualProject);
        info.put("endpoint", actualEndpoint);
        info.put("accessId", actualAccessId);
        info.put("projectOwner", projectInfo.getOwner());
        info.put("projectComment", projectInfo.getComment());
        info.put("projectCreatedTime", projectInfo.getCreatedTime());
        info.put("projectLastModifiedTime", projectInfo.getLastModifiedTime());
        
        // 获取表数量（限制查询以避免性能问题）
        try {
            int tableCount = 0;
            for (Table table : odps.tables()) {
                tableCount++;
                if (tableCount >= 10) break; // 只统计前10个表
            }
            info.put("sampleTableCount", tableCount);
        } catch (Exception e) {
            logger.warn("Failed to get table count: {}", e.getMessage());
            info.put("sampleTableCount", "N/A");
        }

        return info;
    }

    private String getEnvOrConfig(String envName, String configValue) {
        String envValue = System.getenv(envName);
        return (envValue != null && !envValue.isEmpty()) ? envValue : configValue;
    }
}