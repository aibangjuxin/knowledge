package com.aibang.scanner.model;

import java.util.List;
import java.util.ArrayList;
import java.time.LocalDateTime;

/**
 * 扫描结果模型
 */
public class ScanResult {
    private String jarPath;
    private boolean strictMode;
    private boolean passed;
    private LocalDateTime scanTime;
    private List<AuthComponent> jarComponents = new ArrayList<>();
    private List<AuthComponent> configComponents = new ArrayList<>();
    private List<String> recommendations = new ArrayList<>();
    private List<String> errors = new ArrayList<>();
    private List<String> warnings = new ArrayList<>();
    
    public ScanResult() {
        this.scanTime = LocalDateTime.now();
    }
    
    // Getters and Setters
    public String getJarPath() { return jarPath; }
    public void setJarPath(String jarPath) { this.jarPath = jarPath; }
    
    public boolean isStrictMode() { return strictMode; }
    public void setStrictMode(boolean strictMode) { this.strictMode = strictMode; }
    
    public boolean isPassed() { return passed; }
    public void setPassed(boolean passed) { this.passed = passed; }
    
    public LocalDateTime getScanTime() { return scanTime; }
    public void setScanTime(LocalDateTime scanTime) { this.scanTime = scanTime; }
    
    public List<AuthComponent> getJarComponents() { return jarComponents; }
    public void setJarComponents(List<AuthComponent> jarComponents) { this.jarComponents = jarComponents; }
    
    public List<AuthComponent> getConfigComponents() { return configComponents; }
    public void setConfigComponents(List<AuthComponent> configComponents) { this.configComponents = configComponents; }
    
    public List<String> getRecommendations() { return recommendations; }
    public void setRecommendations(List<String> recommendations) { this.recommendations = recommendations; }
    
    public List<String> getErrors() { return errors; }
    public void setErrors(List<String> errors) { this.errors = errors; }
    
    public List<String> getWarnings() { return warnings; }
    public void setWarnings(List<String> warnings) { this.warnings = warnings; }
    
    public void addError(String error) { this.errors.add(error); }
    public void addWarning(String warning) { this.warnings.add(warning); }
    public void addRecommendation(String recommendation) { this.recommendations.add(recommendation); }
}