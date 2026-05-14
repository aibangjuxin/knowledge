package com.aibang.scanner.reporter;

import com.aibang.scanner.model.ScanResult;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;

import java.io.File;
import java.io.IOException;

/**
 * JSON 格式报告生成器
 */
public class JsonReporter {
    
    private final ObjectMapper objectMapper;
    
    public JsonReporter() {
        this.objectMapper = new ObjectMapper();
        this.objectMapper.registerModule(new JavaTimeModule());
        this.objectMapper.enable(SerializationFeature.INDENT_OUTPUT);
        this.objectMapper.disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS);
    }
    
    public String generateReport(ScanResult result) throws IOException {
        return objectMapper.writeValueAsString(result);
    }
    
    public void saveToFile(String report, String filePath) throws IOException {
        File file = new File(filePath);
        file.getParentFile().mkdirs();
        objectMapper.writeValue(file, objectMapper.readValue(report, Object.class));
    }
}