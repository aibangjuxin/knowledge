package com.aibang.scanner.validator;

import com.aibang.scanner.model.AuthComponent;
import com.aibang.scanner.model.ScanResult;

import java.util.List;
import java.util.ArrayList;

/**
 * 认证逻辑验证器
 * 验证应用是否包含完整的认证逻辑
 */
public class AuthValidator {
    
    private List<String> recommendations = new ArrayList<>();
    
    public boolean validate(ScanResult result, boolean strictMode) {
        recommendations.clear();
        
        boolean hasSecurityConfig = hasSecurityConfiguration(result);
        boolean hasAuthAnnotations = hasAuthenticationAnnotations(result);
        boolean hasSecurityDependencies = hasSecurityDependencies(result);
        boolean hasConfigProperties = hasSecurityConfigProperties(result);
        
        // 基本验证规则
        if (!hasSecurityConfig) {
            result.addError("缺少 Spring Security 配置类");
            recommendations.add("添加 @EnableWebSecurity 配置类");
        }
        
        if (!hasAuthAnnotations && !strictMode) {
            result.addWarning("未发现认证注解，可能缺少端点级别的安全控制");
            recommendations.add("在 Controller 方法上添加 @PreAuthorize 或 @Secured 注解");
        } else if (!hasAuthAnnotations && strictMode) {
            result.addError("严格模式下必须包含认证注解");
        }
        
        if (!hasSecurityDependencies) {
            result.addError("缺少安全相关依赖");
            recommendations.add("添加 spring-boot-starter-security 依赖");
        }
        
        // 高级验证
        validateJwtSupport(result);
        validateEndpointSecurity(result);
        
        // 计算总体结果
        boolean passed = result.getErrors().isEmpty();
        if (strictMode) {
            passed = passed && hasSecurityConfig && hasAuthAnnotations && hasSecurityDependencies;
        }
        
        return passed;
    }
    
    private boolean hasSecurityConfiguration(ScanResult result) {
        return result.getJarComponents().stream()
                .anyMatch(c -> c.getType() == AuthComponent.Type.SPRING_SECURITY_CONFIG && c.isFound());
    }
    
    private boolean hasAuthenticationAnnotations(ScanResult result) {
        return result.getJarComponents().stream()
                .anyMatch(c -> c.getType() == AuthComponent.Type.AUTH_ANNOTATION && c.isFound());
    }
    
    private boolean hasSecurityDependencies(ScanResult result) {
        // 这里可以扩展检查 Maven/Gradle 依赖
        return result.getJarComponents().stream()
                .anyMatch(c -> c.getType() == AuthComponent.Type.SECURITY_DEPENDENCY && c.isFound());
    }
    
    private boolean hasSecurityConfigProperties(ScanResult result) {
        return result.getConfigComponents().stream()
                .anyMatch(c -> c.getType() == AuthComponent.Type.CONFIG_PROPERTY && c.isFound());
    }
    
    private void validateJwtSupport(ScanResult result) {
        boolean hasJwtHandler = result.getJarComponents().stream()
                .anyMatch(c -> c.getType() == AuthComponent.Type.JWT_HANDLER && c.isFound());
        
        boolean hasJwtConfig = result.getConfigComponents().stream()
                .anyMatch(c -> c.getName().contains("jwt"));
        
        if (!hasJwtHandler && !hasJwtConfig) {
            result.addWarning("未发现 JWT 支持，如果使用 JWT 认证请确保正确配置");
            recommendations.add("添加 JWT 处理器和相关配置");
        }
    }
    
    private void validateEndpointSecurity(ScanResult result) {
        // 检查是否有端点安全配置
        boolean hasEndpointSecurity = result.getJarComponents().stream()
                .anyMatch(c -> c.getType() == AuthComponent.Type.ENDPOINT_SECURITY && c.isFound());
        
        if (!hasEndpointSecurity) {
            result.addWarning("建议配置端点级别的安全策略");
            recommendations.add("在 SecurityConfig 中配置 HTTP 安全规则");
        }
    }
    
    public List<String> getRecommendations() {
        return new ArrayList<>(recommendations);
    }
}