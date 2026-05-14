package com.aibang.scanner;

import com.aibang.scanner.model.ScanResult;
import com.aibang.scanner.model.AuthComponent;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.io.TempDir;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.file.Path;
import java.util.jar.JarOutputStream;
import java.util.jar.JarEntry;

import static org.junit.jupiter.api.Assertions.*;

class AuthScannerTest {
    
    private AuthScanner scanner;
    
    @BeforeEach
    void setUp() {
        scanner = new AuthScanner();
    }
    
    @Test
    void testScanEmptyJar(@TempDir Path tempDir) throws Exception {
        // 创建一个空的 JAR 文件
        File jarFile = tempDir.resolve("empty.jar").toFile();
        createEmptyJar(jarFile);
        
        // 执行扫描
        ScanResult result = scanner.scan(jarFile.getAbsolutePath(), null, false);
        
        // 验证结果
        assertNotNull(result);
        assertFalse(result.isPassed()); // 空 JAR 应该扫描失败
        assertTrue(result.getErrors().size() > 0);
    }
    
    @Test
    void testScanWithStrictMode(@TempDir Path tempDir) throws Exception {
        File jarFile = tempDir.resolve("test.jar").toFile();
        createEmptyJar(jarFile);
        
        // 严格模式扫描
        ScanResult result = scanner.scan(jarFile.getAbsolutePath(), null, true);
        
        assertNotNull(result);
        assertTrue(result.isStrictMode());
        assertFalse(result.isPassed());
    }
    
    @Test
    void testScanResultStructure(@TempDir Path tempDir) throws Exception {
        File jarFile = tempDir.resolve("test.jar").toFile();
        createEmptyJar(jarFile);
        
        ScanResult result = scanner.scan(jarFile.getAbsolutePath(), null, false);
        
        // 验证结果结构
        assertNotNull(result.getJarPath());
        assertNotNull(result.getScanTime());
        assertNotNull(result.getJarComponents());
        assertNotNull(result.getConfigComponents());
        assertNotNull(result.getErrors());
        assertNotNull(result.getWarnings());
        assertNotNull(result.getRecommendations());
    }
    
    private void createEmptyJar(File jarFile) throws IOException {
        try (JarOutputStream jos = new JarOutputStream(new FileOutputStream(jarFile))) {
            // 添加一个空的 manifest
            JarEntry entry = new JarEntry("META-INF/MANIFEST.MF");
            jos.putNextEntry(entry);
            jos.write("Manifest-Version: 1.0\n".getBytes());
            jos.closeEntry();
        }
    }
}