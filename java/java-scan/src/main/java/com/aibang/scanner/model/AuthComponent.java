package com.aibang.scanner.model;

/**
 * 认证组件模型
 */
public class AuthComponent {
    
    public enum Type {
        SPRING_SECURITY_CONFIG,    // Spring Security 配置类
        JWT_HANDLER,               // JWT 处理器
        OAUTH2_CONFIG,             // OAuth2 配置
        CUSTOM_FILTER,             // 自定义过滤器
        AUTH_ANNOTATION,           // 认证注解
        SECURITY_DEPENDENCY,       // 安全相关依赖
        CONFIG_PROPERTY,           // 配置属性
        ENDPOINT_SECURITY          // 端点安全配置
    }
    
    private Type type;
    private String name;
    private String className;
    private String description;
    private boolean required;
    private boolean found;
    private String location;
    
    public AuthComponent(Type type, String name) {
        this.type = type;
        this.name = name;
        this.required = false;
        this.found = false;
    }
    
    // Getters and Setters
    public Type getType() { return type; }
    public void setType(Type type) { this.type = type; }
    
    public String getName() { return name; }
    public void setName(String name) { this.name = name; }
    
    public String getClassName() { return className; }
    public void setClassName(String className) { this.className = className; }
    
    public String getDescription() { return description; }
    public void setDescription(String description) { this.description = description; }
    
    public boolean isRequired() { return required; }
    public void setRequired(boolean required) { this.required = required; }
    
    public boolean isFound() { return found; }
    public void setFound(boolean found) { this.found = found; }
    
    public String getLocation() { return location; }
    public void setLocation(String location) { this.location = location; }
    
    @Override
    public String toString() {
        return String.format("AuthComponent{type=%s, name='%s', found=%s, location='%s'}", 
                           type, name, found, location);
    }
}