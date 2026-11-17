package com.aibang.scanner;

import com.aibang.scanner.analyzer.JarAnalyzer;
import com.aibang.scanner.analyzer.ConfigAnalyzer;
import com.aibang.scanner.model.ScanResult;
import com.aibang.scanner.reporter.JsonReporter;
import com.fasterxml.jackson.databind.ObjectMapper;

import java.io.File;
import java.util.Arrays;

/**
 * 认证扫描工具主入口
 * 用于扫描 Java 应用是否包含必要的认证逻辑
 */
public class AuthScannerMain {
    
    public static void main(String[] args) {
        if (args.length < 1) {
            System.err.println("Usage: java -jar auth-scanner.jar <jar-file-path> [options]");
            System.err.println("Options:");
            System.err.println("  --config-path <path>  指定配置文件路径");
            System.err.println("  --output <file>       输出报告文件");
            System.err.println("  --strict             严格模式，缺少任何认证组件都失败");
            System.exit(1);
        }
        
        String jarPath = args[0];
        String configPath = getArgValue(args, "--config-path");
        String outputFile = getArgValue(args, "--output");
        boolean strictMode = Arrays.asList(args).contains("--strict");
        
        try {
            AuthScanner scanner = new AuthScanner();
            ScanResult result = scanner.scan(jarPath, configPath, strictMode);
            
            // 输出结果
            JsonReporter reporter = new JsonReporter();
            String report = reporter.generateReport(result);
            
            if (outputFile != null) {
                reporter.saveToFile(report, outputFile);
                System.out.println("扫描报告已保存到: " + outputFile);
            } else {
                System.out.println(report);
            }
            
            // 根据扫描结果设置退出码
            System.exit(result.isPassed() ? 0 : 1);
            
        } catch (Exception e) {
            System.err.println("扫描失败: " + e.getMessage());
            e.printStackTrace();
            System.exit(1);
        }
    }
    
    private static String getArgValue(String[] args, String option) {
        for (int i = 0; i < args.length - 1; i++) {
            if (option.equals(args[i])) {
                return args[i + 1];
            }
        }
        return null;
    }
}