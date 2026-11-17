package com.aibang.scanner;

import java.util.ArrayList;
import java.util.List;

public class ScanResult {
    private String status; // PASSED, FAILED
    private List<Issue> issues = new ArrayList<>();
    private int scannedClasses = 0;
    private int scannedControllers = 0;

    public void addIssue(Issue issue) {
        this.issues.add(issue);
        this.status = "FAILED";
    }

    public boolean hasErrors() {
        return !issues.isEmpty();
    }

    public String getStatus() {
        return issues.isEmpty() ? "PASSED" : "FAILED";
    }

    public List<Issue> getIssues() {
        return issues;
    }

    public int getScannedClasses() {
        return scannedClasses;
    }

    public void incrementScannedClasses() {
        this.scannedClasses++;
    }

    public int getScannedControllers() {
        return scannedControllers;
    }

    public void incrementScannedControllers() {
        this.scannedControllers++;
    }
}

class Issue {
    public String className;
    public String methodName;
    public String message;
    public String severity;

    public Issue(String className, String methodName, String message, String severity) {
        this.className = className;
        this.methodName = methodName;
        this.message = message;
        this.severity = severity;
    }
}
