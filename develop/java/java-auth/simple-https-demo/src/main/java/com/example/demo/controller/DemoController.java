package com.example.demo.controller;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import javax.net.ssl.HttpsURLConnection;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.net.URI;
import java.net.URL;
import java.util.HashMap;
import java.util.Map;

@RestController
public class DemoController {

    // Test endpoint: https://localhost:8443/hello
    @GetMapping("/hello")
    public Map<String, String> hello() {
        Map<String, String> response = new HashMap<>();
        response.put("message", "Hello from HTTPS Server on port 8443!");
        response.put("ssl", "Your own certificate is working");
        return response;
    }

    // Test outbound HTTPS call using Java's built-in cacerts
    // Example: https://localhost:8443/fetch?url=https://httpbin.org/get
    @GetMapping("/fetch")
    public Map<String, Object> fetchExternal(@RequestParam String url) {
        Map<String, Object> result = new HashMap<>();
        result.put("targetUrl", url);

        try {
            URL targetUrl = URI.create(url).toURL();
            HttpsURLConnection conn = (HttpsURLConnection) targetUrl.openConnection();
            conn.setRequestMethod("GET");
            conn.setConnectTimeout(5000);
            conn.setReadTimeout(5000);

            int responseCode = conn.getResponseCode();
            result.put("responseCode", responseCode);

            StringBuilder content = new StringBuilder();
            try (BufferedReader reader = new BufferedReader(
                    new InputStreamReader(conn.getInputStream()))) {
                String line;
                while ((line = reader.readLine()) != null) {
                    content.append(line);
                }
            }

            // Truncate response if too long
            String body = content.toString();
            if (body.length() > 500) {
                body = body.substring(0, 500) + "... (truncated)";
            }
            result.put("body", body);
            result.put("status", "SUCCESS - Java built-in cacerts worked!");

        } catch (Exception e) {
            result.put("status", "ERROR");
            result.put("error", e.getClass().getSimpleName() + ": " + e.getMessage());
        }

        return result;
    }
}
