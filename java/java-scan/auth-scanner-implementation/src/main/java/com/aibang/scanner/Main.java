package com.aibang.scanner;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;

import java.io.File;
import java.io.IOException;

public class Main {
    public static void main(String[] args) {
        if (args.length < 1) {
            System.err.println("Usage: java -jar auth-scanner.jar <path-to-jar> [--output <output-file>]");
            System.exit(1);
        }

        String jarPath = args[0];
        String outputPath = "scan-report.json";

        if (args.length >= 3 && args[1].equals("--output")) {
            outputPath = args[2];
        }

        System.out.println("Scanning JAR: " + jarPath);

        try {
            Scanner scanner = new Scanner(jarPath);
            ScanResult result = scanner.scan();

            ObjectMapper mapper = new ObjectMapper();
            mapper.enable(SerializationFeature.INDENT_OUTPUT);

            File outputFile = new File(outputPath);
            mapper.writeValue(outputFile, result);

            System.out.println("Scan complete. Report written to: " + outputFile.getAbsolutePath());
            System.out.println("Status: " + result.getStatus());
            System.out.println("Issues found: " + result.getIssues().size());

            if (result.hasErrors()) {
                System.exit(1);
            }
        } catch (IOException e) {
            System.err.println("Error scanning JAR: " + e.getMessage());
            e.printStackTrace();
            System.exit(1);
        }
    }
}
