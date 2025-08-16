package com.example.controller;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.HashMap;
import java.util.Map;

@RestController
@RequestMapping("/api")
public class TimeoutController {

    @GetMapping("/timeout")
    public ResponseEntity<Map<String, Object>> handleRequest(
            @RequestParam(defaultValue = "0") int timeout) throws InterruptedException {
        
        long startTime = System.currentTimeMillis();
        
        // Convert timeout to milliseconds and sleep
        int delay = timeout * 1000;
        Thread.sleep(delay);
        
        long endTime = System.currentTimeMillis();
        long actualDelay = endTime - startTime;
        
        Map<String, Object> response = new HashMap<>();
        response.put("message", "Request completed after " + timeout + " seconds delay");
        response.put("requestedTimeout", timeout);
        response.put("actualDelayMs", actualDelay);
        response.put("timestamp", LocalDateTime.now().format(DateTimeFormatter.ISO_LOCAL_DATE_TIME));
        response.put("status", "success");
        
        return ResponseEntity.ok(response);
    }

    @GetMapping("/health")
    public ResponseEntity<Map<String, String>> health() {
        Map<String, String> response = new HashMap<>();
        response.put("status", "UP");
        response.put("timestamp", LocalDateTime.now().format(DateTimeFormatter.ISO_LOCAL_DATE_TIME));
        return ResponseEntity.ok(response);
    }
}