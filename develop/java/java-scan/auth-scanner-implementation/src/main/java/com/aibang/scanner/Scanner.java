package com.aibang.scanner;

import org.objectweb.asm.ClassReader;

import java.io.IOException;
import java.io.InputStream;
import java.util.Enumeration;
import java.util.jar.JarEntry;
import java.util.jar.JarFile;

public class Scanner {
    private String jarPath;

    public Scanner(String jarPath) {
        this.jarPath = jarPath;
    }

    public ScanResult scan() throws IOException {
        ScanResult result = new ScanResult();
        try (JarFile jarFile = new JarFile(jarPath)) {
            Enumeration<JarEntry> entries = jarFile.entries();
            while (entries.hasMoreElements()) {
                JarEntry entry = entries.nextElement();
                if (entry.getName().endsWith(".class")) {
                    result.incrementScannedClasses();
                    try (InputStream is = jarFile.getInputStream(entry)) {
                        ClassReader reader = new ClassReader(is);
                        AuthClassVisitor visitor = new AuthClassVisitor(result);
                        reader.accept(visitor, 0);
                    }
                }
            }
        }
        return result;
    }
}
