package com.company.maxcompute.controller;

import com.company.maxcompute.service.MaxComputeHealthService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.HashMap;
import java.util.Map;

@RestController
@RequestMapping("/api")
public class MaxComputeHealthController {

    @Autowired
    private MaxComputeHealthService maxComputeHealthService;

    @GetMapping("/max_computer/health")
    public ResponseEntity<Map<String, Object>> checkMaxComputeHealth() {
        Map<String, Object> response = new HashMap<>();
        
        try {
            boolean isHealthy = maxComputeHealthService.checkConnection();
            
            if (isHealthy) {
                response.put("status", "SUCCESS");
                response.put("message", "MaxCompute Connection Success");
                response.put("timestamp", System.currentTimeMillis());
                return ResponseEntity.ok(response);
            } else {
                response.put("status", "FAILED");
                response.put("message", "MaxCompute Connection Failed");
                response.put("timestamp", System.currentTimeMillis());
                return ResponseEntity.status(503).body(response);
            }
        } catch (Exception e) {
            response.put("status", "ERROR");
            response.put("message", "MaxCompute Connection Error: " + e.getMessage());
            response.put("timestamp", System.currentTimeMillis());
            return ResponseEntity.status(500).body(response);
        }
    }

    @GetMapping("/max_computer/info")
    public ResponseEntity<Map<String, Object>> getMaxComputeInfo() {
        Map<String, Object> response = new HashMap<>();
        
        try {
            Map<String, Object> info = maxComputeHealthService.getConnectionInfo();
            response.put("status", "SUCCESS");
            response.put("data", info);
            response.put("timestamp", System.currentTimeMillis());
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            response.put("status", "ERROR");
            response.put("message", "Failed to get MaxCompute info: " + e.getMessage());
            response.put("timestamp", System.currentTimeMillis());
            return ResponseEntity.status(500).body(response);
        }
    }
}