package com.aibang.scanner;

import org.objectweb.asm.AnnotationVisitor;
import org.objectweb.asm.ClassVisitor;
import org.objectweb.asm.MethodVisitor;
import org.objectweb.asm.Opcodes;

import java.util.Set;

public class AuthClassVisitor extends ClassVisitor {
    private String className;
    private boolean isController = false;
    private boolean hasClassLevelAuth = false;
    private ScanResult result;

    private static final Set<String> CONTROLLER_ANNOTATIONS = Set.of(
            "Lorg/springframework/web/bind/annotation/RestController;",
            "Lorg/springframework/stereotype/Controller;");

    private static final Set<String> AUTH_ANNOTATIONS = Set.of(
            "Lorg/springframework/security/access/prepost/PreAuthorize;",
            "Lorg/springframework/security/access/annotation/Secured;",
            "Ljavax/annotation/security/RolesAllowed;",
            "Ljakarta/annotation/security/RolesAllowed;");

    private static final Set<String> MAPPING_ANNOTATIONS = Set.of(
            "Lorg/springframework/web/bind/annotation/RequestMapping;",
            "Lorg/springframework/web/bind/annotation/GetMapping;",
            "Lorg/springframework/web/bind/annotation/PostMapping;",
            "Lorg/springframework/web/bind/annotation/PutMapping;",
            "Lorg/springframework/web/bind/annotation/DeleteMapping;",
            "Lorg/springframework/web/bind/annotation/PatchMapping;");

    public AuthClassVisitor(ScanResult result) {
        super(Opcodes.ASM9);
        this.result = result;
    }

    @Override
    public void visit(int version, int access, String name, String signature, String superName, String[] interfaces) {
        this.className = name.replace('/', '.');
        super.visit(version, access, name, signature, superName, interfaces);
    }

    @Override
    public AnnotationVisitor visitAnnotation(String descriptor, boolean visible) {
        if (CONTROLLER_ANNOTATIONS.contains(descriptor)) {
            isController = true;
            result.incrementScannedControllers();
        }
        if (AUTH_ANNOTATIONS.contains(descriptor)) {
            hasClassLevelAuth = true;
        }
        return super.visitAnnotation(descriptor, visible);
    }

    @Override
    public MethodVisitor visitMethod(int access, String name, String descriptor, String signature,
            String[] exceptions) {
        if (!isController) {
            return super.visitMethod(access, name, descriptor, signature, exceptions);
        }
        // Skip constructors and static blocks
        if (name.equals("<init>") || name.equals("<clinit>")) {
            return super.visitMethod(access, name, descriptor, signature, exceptions);
        }

        return new AuthMethodVisitor(Opcodes.ASM9, name, descriptor, hasClassLevelAuth, className, result);
    }

    static class AuthMethodVisitor extends MethodVisitor {
        String methodName;
        String descriptor;
        boolean hasClassLevelAuth;
        String className;
        ScanResult result;

        boolean isMapping = false;
        boolean hasMethodAuth = false;

        public AuthMethodVisitor(int api, String methodName, String descriptor, boolean hasClassLevelAuth,
                String className, ScanResult result) {
            super(api);
            this.methodName = methodName;
            this.descriptor = descriptor;
            this.hasClassLevelAuth = hasClassLevelAuth;
            this.className = className;
            this.result = result;
        }

        @Override
        public AnnotationVisitor visitAnnotation(String descriptor, boolean visible) {
            if (MAPPING_ANNOTATIONS.contains(descriptor)) {
                isMapping = true;
            }
            if (AUTH_ANNOTATIONS.contains(descriptor)) {
                hasMethodAuth = true;
            }
            return super.visitAnnotation(descriptor, visible);
        }

        @Override
        public void visitEnd() {
            if (isMapping) {
                // It's an endpoint. Check if it's secured.
                if (!hasClassLevelAuth && !hasMethodAuth) {
                    result.addIssue(new Issue(
                            className,
                            methodName,
                            "Endpoint is not secured with @PreAuthorize or similar annotations.",
                            "HIGH"));
                }
            }
            super.visitEnd();
        }
    }
}
