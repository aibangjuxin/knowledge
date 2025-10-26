package com.aibang.scanner.analyzer;

import com.aibang.scanner.model.AuthComponent;
import org.objectweb.asm.ClassReader;
import org.objectweb.asm.ClassVisitor;
import org.objectweb.asm.AnnotationVisitor;
import org.objectweb.asm.Opcodes;

import java.io.File;
import java.io.InputStream;
import java.util.List;
import java.util.ArrayList;
import java.util.jar.JarFile;
import java.util.jar.JarEntry;
import java.util.Enumeration;

/**
 * JAR 文件分析器
 * 使用 ASM 分析字节码，查找认证相关的类和注解
 */
public class JarAnalyzer {
    
    private static final String[] SECURITY_ANNOTATIONS = {
        "org/springframework/security/access/prepost/PreAuthorize",
        "org/springframework/security/access/annotation/Secured",
        "javax/annotation/security/RolesAllowed",
        "org/springframework/web/bind/annotation/RestController",
        "org/springframework/stereotype/Controller"
    };
    
    private static final String[] SECURITY_CLASSES = {
        "org/springframework/security/config/annotation/web/configuration/WebSecurityConfigurerAdapter",
        "org/springframework/security/config/annotation/web/configuration/WebSecurityConfigurer",
        "org/springframework/security/web/SecurityFilterChain",
        "org/springframework/security/authentication/AuthenticationProvider",
        "org/springframework/security/core/userdetails/UserDetailsService"
    };
    
    public List<AuthComponent> analyze(File jarFile) throws Exception {
        List<AuthComponent> components = new ArrayList<>();
        
        try (JarFile jar = new JarFile(jarFile)) {
            Enumeration<JarEntry> entries = jar.entries();
            
            while (entries.hasMoreElements()) {
                JarEntry entry = entries.nextElement();
                
                if (entry.getName().endsWith(".class")) {
                    try (InputStream is = jar.getInputStream(entry)) {
                        ClassReader reader = new ClassReader(is);
                        AuthClassVisitor visitor = new AuthClassVisitor(components, entry.getName());
                        reader.accept(visitor, ClassReader.SKIP_DEBUG);
                    }
                }
            }
        }
        
        return components;
    }
    
    /**
     * ASM ClassVisitor 用于分析类的认证相关特征
     */
    private static class AuthClassVisitor extends ClassVisitor {
        private final List<AuthComponent> components;
        private final String location;
        private String className;
        
        public AuthClassVisitor(List<AuthComponent> components, String location) {
            super(Opcodes.ASM9);
            this.components = components;
            this.location = location;
        }
        
        @Override
        public void visit(int version, int access, String name, String signature, 
                         String superName, String[] interfaces) {
            this.className = name.replace('/', '.');
            
            // 检查是否继承了安全相关的基类
            if (superName != null) {
                for (String securityClass : SECURITY_CLASSES) {
                    if (superName.equals(securityClass)) {
                        AuthComponent component = new AuthComponent(
                            AuthComponent.Type.SPRING_SECURITY_CONFIG, 
                            className
                        );
                        component.setFound(true);
                        component.setLocation(location);
                        component.setDescription("Spring Security 配置类");
                        components.add(component);
                        break;
                    }
                }
            }
            
            // 检查实现的接口
            if (interfaces != null) {
                for (String iface : interfaces) {
                    for (String securityClass : SECURITY_CLASSES) {
                        if (iface.equals(securityClass)) {
                            AuthComponent component = new AuthComponent(
                                AuthComponent.Type.SPRING_SECURITY_CONFIG, 
                                className
                            );
                            component.setFound(true);
                            component.setLocation(location);
                            component.setDescription("实现安全接口: " + iface.replace('/', '.'));
                            components.add(component);
                            break;
                        }
                    }
                }
            }
        }
        
        @Override
        public AnnotationVisitor visitAnnotation(String descriptor, boolean visible) {
            // 检查安全相关注解
            for (String securityAnnotation : SECURITY_ANNOTATIONS) {
                if (descriptor.contains(securityAnnotation.replace('/', '.'))) {
                    AuthComponent component = new AuthComponent(
                        AuthComponent.Type.AUTH_ANNOTATION, 
                        className
                    );
                    component.setFound(true);
                    component.setLocation(location);
                    component.setDescription("包含安全注解: " + descriptor);
                    components.add(component);
                    break;
                }
            }
            
            return super.visitAnnotation(descriptor, visible);
        }
    }
}