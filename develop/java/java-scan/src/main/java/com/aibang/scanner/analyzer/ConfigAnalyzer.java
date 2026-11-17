package com.aibang.scanner.analyzer;

import com.aibang.scanner.model.AuthComponent;
import org.yaml.snakeyaml.Yaml;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.util.List;
import java.util.ArrayList;
import java.util.Map;
import java.util.Properties;

/**
 * 配置文件分析器
 * 分析 application.yml, application.properties 等配置文件中的安全配置
 */
public class ConfigAnalyzer {
    
    private static final String[] SECURITY_PROPERTIES = {
        "spring.security",
        "security.oauth2",
        "jwt.secret",
        "jwt.expiration",
        "auth.enabled",
        "security.enabled"
    };
    
    public List<AuthComponent> analyze(String configPath) throws IOException {
        List<AuthComponent> components = new ArrayList<>();
        File configDir = new File(configPath);
        
        if (configDir.isDirectory()) {
            analyzeDirectory(configDir, components);
        } else if (configDir.isFile()) {
            analyzeFile(configDir, components);
        }
        
        return components;
    }
    
    private void analyzeDirectory(File dir, List<AuthComponent> components) throws IOException {
        File[] files = dir.listFiles();
        if (files != null) {
            for (File file : files) {
                if (file.isFile() && isConfigFile(file.getName())) {
                    analyzeFile(file, components);
                }
            }
        }
    }
    
    private void analyzeFile(File file, List<AuthComponent> components) throws IOException {
        String fileName = file.getName();
        
        if (fileName.endsWith(".yml") || fileName.endsWith(".yaml")) {
            analyzeYamlFile(file, components);
        } else if (fileName.endsWith(".properties")) {
            analyzePropertiesFile(file, components);
        }
    }
    
    private void analyzeYamlFile(File file, List<AuthComponent> components) throws IOException {
        try (FileInputStream fis = new FileInputStream(file)) {
            Yaml yaml = new Yaml();
            Map<String, Object> data = yaml.load(fis);
            
            if (data != null) {
                analyzeConfigMap(data, "", file.getPath(), components);
            }
        }
    }
    
    private void analyzePropertiesFile(File file, List<AuthComponent> components) throws IOException {
        Properties props = new Properties();
        try (FileInputStream fis = new FileInputStream(file)) {
            props.load(fis);
            
            for (String key : props.stringPropertyNames()) {
                checkSecurityProperty(key, props.getProperty(key), file.getPath(), components);
            }
        }
    }
    
    @SuppressWarnings("unchecked")
    private void analyzeConfigMap(Map<String, Object> map, String prefix, String location, 
                                 List<AuthComponent> components) {
        for (Map.Entry<String, Object> entry : map.entrySet()) {
            String key = prefix.isEmpty() ? entry.getKey() : prefix + "." + entry.getKey();
            Object value = entry.getValue();
            
            if (value instanceof Map) {
                analyzeConfigMap((Map<String, Object>) value, key, location, components);
            } else {
                checkSecurityProperty(key, String.valueOf(value), location, components);
            }
        }
    }
    
    private void checkSecurityProperty(String key, String value, String location, 
                                     List<AuthComponent> components) {
        for (String securityProp : SECURITY_PROPERTIES) {
            if (key.startsWith(securityProp)) {
                AuthComponent component = new AuthComponent(
                    AuthComponent.Type.CONFIG_PROPERTY, 
                    key
                );
                component.setFound(true);
                component.setLocation(location);
                component.setDescription("安全配置属性: " + key + " = " + value);
                components.add(component);
                break;
            }
        }
    }
    
    private boolean isConfigFile(String fileName) {
        return fileName.equals("application.yml") ||
               fileName.equals("application.yaml") ||
               fileName.equals("application.properties") ||
               fileName.startsWith("application-") && 
               (fileName.endsWith(".yml") || fileName.endsWith(".yaml") || fileName.endsWith(".properties"));
    }
}