import config.AppProperties;
import service.AuthenticationService;
import service.SecretManagerService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.Map;

/**
 * Main Spring Boot application demonstrating GCP Secret Manager integration
 * with both key-value and file-based secrets.
 */
@SpringBootApplication
@EnableConfigurationProperties(AppProperties.class)
public class SecretManagerDemo {
    
    private static final Logger logger = LoggerFactory.getLogger(SecretManagerDemo.class);
    
    @Autowired
    private SecretManagerService secretManagerService;
    
    @Autowired
    private AuthenticationService authenticationService;
    
    @Autowired
    private AppProperties appProperties;
    
    public static void main(String[] args) {
        SpringApplication.run(SecretManagerDemo.class, args);
    }
    
    /**
     * Application runner to demonstrate secret retrieval on startup.
     */
    @Bean
    public ApplicationRunner demoRunner() {
        return args -> {
            logger.info("=== GCP Secret Manager Demo Started ===");
            
            try {
                demonstrateKeyValueSecrets();
                demonstrateFileSecrets();
                demonstrateAuthentication();
                
                logger.info("=== Demo completed successfully ===");
                
            } catch (Exception e) {
                logger.error("Demo failed", e);
            }
        };
    }
    
    /**
     * Demonstrates key-value secret retrieval.
     */
    private void demonstrateKeyValueSecrets() {
        logger.info("--- Demonstrating Key-Value Secrets ---");
        
        try {
            // These are automatically injected from application.yml using sm:// protocol
            String dbPassword = appProperties.getSecrets().getDatabasePassword();
            String apiKey = appProperties.getSecrets().getApiKey();
            
            logger.info("Database password loaded: {}", maskSecret(dbPassword));
            logger.info("API key loaded: {}", maskSecret(apiKey));
            
            // You can also retrieve secrets programmatically
            String jwtSecret = secretManagerService.getKeyValueSecret("jwt-signing-key");
            logger.info("JWT secret retrieved programmatically: {}", maskSecret(jwtSecret));
            
        } catch (Exception e) {
            logger.error("Failed to demonstrate key-value secrets", e);
        }
    }
    
    /**
     * Demonstrates file-based secret retrieval.
     */
    private void demonstrateFileSecrets() {
        logger.info("--- Demonstrating File-Based Secrets ---");
        
        try {
            // Retrieve keystore file from Secret Manager
            String keystoreSecretName = appProperties.getSecrets().getKeystoreFile();
            String keystorePath = appProperties.getSecretFiles().getKeystorePath();
            
            if (keystoreSecretName != null && keystorePath != null) {
                // Write the keystore file to the specified path
                secretManagerService.writeFileSecretToPath(keystoreSecretName, keystorePath);
                logger.info("Keystore file written to: {}", keystorePath);
            }
            
            // Retrieve SSL certificate
            String sslCertSecretName = appProperties.getSecrets().getSslCertificate();
            String sslCertPath = appProperties.getSecretFiles().getSslCertPath();
            
            if (sslCertSecretName != null && sslCertPath != null) {
                secretManagerService.writeFileSecretToPath(sslCertSecretName, sslCertPath);
                logger.info("SSL certificate written to: {}", sslCertPath);
            }
            
            // You can also get file content as byte array for direct use
            if (keystoreSecretName != null) {
                byte[] keystoreContent = secretManagerService.getFileSecret(keystoreSecretName);
                logger.info("Keystore content retrieved as byte array, size: {} bytes", keystoreContent.length);
            }
            
        } catch (Exception e) {
            logger.error("Failed to demonstrate file-based secrets", e);
        }
    }
    
    /**
     * Demonstrates authentication using secrets.
     */
    private void demonstrateAuthentication() {
        logger.info("--- Demonstrating Authentication with Secrets ---");
        
        try {
            // Test user authentication
            boolean authResult = authenticationService.authenticateUser("admin", 
                appProperties.getSecrets().getDatabasePassword());
            logger.info("Admin authentication result: {}", authResult);
            
            // Test API key validation
            boolean apiKeyValid = authenticationService.validateApiKey(
                appProperties.getSecrets().getApiKey());
            logger.info("API key validation result: {}", apiKeyValid);
            
        } catch (Exception e) {
            logger.error("Failed to demonstrate authentication", e);
        }
    }
    
    /**
     * Masks a secret for safe logging.
     */
    private String maskSecret(String secret) {
        if (secret == null || secret.length() < 4) {
            return "***";
        }
        return secret.substring(0, 2) + "***" + secret.substring(secret.length() - 2);
    }
    
    /**
     * REST Controller for demonstrating the application functionality.
     */
    @RestController
    @RequestMapping("/api")
    public static class DemoController {
        
        @Autowired
        private SecretManagerService secretManagerService;
        
        @Autowired
        private AuthenticationService authenticationService;
        
        @Autowired
        private AppProperties appProperties;
        
        /**
         * Health check endpoint.
         */
        @GetMapping("/health")
        public ResponseEntity<Map<String, Object>> health() {
            Map<String, Object> response = new HashMap<>();
            response.put("status", "UP");
            response.put("timestamp", System.currentTimeMillis());
            response.put("secretsConfigured", appProperties.getSecrets() != null);
            return ResponseEntity.ok(response);
        }
        
        /**
         * Login endpoint demonstrating authentication with secrets.
         */
        @PostMapping("/login")
        public ResponseEntity<Map<String, Object>> login(@RequestBody LoginRequest request) {
            Map<String, Object> response = new HashMap<>();
            
            boolean authenticated = authenticationService.authenticateUser(
                request.getUsername(), request.getPassword());
            
            if (authenticated) {
                response.put("success", true);
                response.put("message", "Authentication successful");
                response.put("token", "jwt-token-would-be-here");
            } else {
                response.put("success", false);
                response.put("message", "Authentication failed");
            }
            
            return ResponseEntity.ok(response);
        }
        
        /**
         * API key validation endpoint.
         */
        @PostMapping("/validate-api-key")
        public ResponseEntity<Map<String, Object>> validateApiKey(@RequestHeader("X-API-Key") String apiKey) {
            Map<String, Object> response = new HashMap<>();
            
            boolean valid = authenticationService.validateApiKey(apiKey);
            response.put("valid", valid);
            response.put("message", valid ? "API key is valid" : "Invalid API key");
            
            return ResponseEntity.ok(response);
        }
        
        /**
         * Get application statistics.
         */
        @GetMapping("/stats")
        public ResponseEntity<Map<String, Object>> getStats() {
            Map<String, Object> response = new HashMap<>();
            response.put("cache", secretManagerService.getCacheStats());
            response.put("auth", authenticationService.getAuthStats());
            return ResponseEntity.ok(response);
        }
        
        /**
         * Retrieve a specific secret (for testing purposes).
         */
        @GetMapping("/secret/{secretName}")
        public ResponseEntity<Map<String, Object>> getSecret(@PathVariable String secretName) {
            Map<String, Object> response = new HashMap<>();
            
            try {
                String secretValue = secretManagerService.getKeyValueSecret(secretName);
                response.put("success", true);
                response.put("secretName", secretName);
                response.put("secretValue", maskSecretForResponse(secretValue));
            } catch (Exception e) {
                response.put("success", false);
                response.put("error", e.getMessage());
            }
            
            return ResponseEntity.ok(response);
        }
        
        private String maskSecretForResponse(String secret) {
            if (secret == null || secret.length() < 4) {
                return "***";
            }
            return secret.substring(0, 2) + "***" + secret.substring(secret.length() - 2);
        }
    }
    
    /**
     * Login request DTO.
     */
    public static class LoginRequest {
        private String username;
        private String password;
        
        public String getUsername() {
            return username;
        }
        
        public void setUsername(String username) {
            this.username = username;
        }
        
        public String getPassword() {
            return password;
        }
        
        public void setPassword(String password) {
            this.password = password;
        }
    }
}