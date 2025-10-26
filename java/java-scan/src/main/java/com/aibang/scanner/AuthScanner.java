package com.aibang.scanner;

import com.aibang.scanner.analyzer.JarAnalyzer;
import com.aibang.scanner.analyzer.ConfigAnalyzer;
import com.aibang.scanner.model.ScanResult;
import com.aibang.scanner.model.AuthComponent;
import com.aibang.scanner.validator.AuthValidator;

import java.io.File;
import java.util.List;
import java.util.ArrayList;

/**
 * 认证扫描器核心类
 */
public class AuthScanner {
    
    private final JarAnalyzer jarAnalyzer;
    private final ConfigAnalyzer configAnalyzer;
    private final AuthValidator validator;
    
    public AuthScanner() {
        this.jarAnalyzer = new JarAnalyzer();
        this.configAnalyzer = new ConfigAnalyzer();
        this.validator = new AuthValidator();
    }
    
    /**
     * 执行完整的认证扫描
     */
    public ScanResult scan(String jarPath, String configPath, boolean strictMode) throws Exception {
        File jarFile = new File(jarPath);
        if (!jarFile.exists()) {
            throw new IllegalArgumentException("JAR 文件不存在: " + jarPath);
        }
        
        ScanResult result = new ScanResult();
        result.setJarPath(jarPath);
        result.setStrictMode(strictMode);
        
        // 1. 分析 JAR 文件
        List<AuthComponent> jarComponents = jarAnalyzer.analyze(jarFile);
        result.setJarComponents(jarComponents);
        
        // 2. 分析配置文件
        if (configPath != null) {
            List<AuthComponent> configComponents = configAnalyzer.analyze(configPath);
            result.setConfigComponents(configComponents);
        }
        
        // 3. 验证认证逻辑完整性
        boolean isValid = validator.validate(result, strictMode);
        result.setPassed(isValid);
        
        // 4. 生成建议
        result.setRecommendations(validator.getRecommendations());
        
        return result;
    }
}