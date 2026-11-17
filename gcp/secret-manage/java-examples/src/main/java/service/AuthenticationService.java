package service;

import config.AppProperties;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

import javax.annotation.PostConstruct;
import java.util.HashMap;
import java.util.Map;

/**
 * Authentication service that demonstrates using secrets from Secret Manager
 * for user authentication and API key validation.
 */
@Service
public class AuthenticationService {
    
    private static final Logger logger = LoggerFactory.getLogger(AuthenticationService.class);
    
    private final SecretManagerService secretManagerService;
    private final PasswordEncoder passwordEncoder;
    private final AppProperties appProperties;
    
    // In-memory user store for demo purposes
    private final Map<String, String> userPasswords = new HashMap<>();
    private String apiKey;
    private String jwtSecret;
    
    @Autowired
    public AuthenticationService(SecretManagerService secretManagerService, 
                               PasswordEncoder passwordEncoder,
                               AppProperties appProperties) {
        this.secretManagerService = secretManagerService;
        this.passwordEncoder = passwordEncoder;
        this.appProperties = appProperties;
    }
    
    /**
     * Initialize authentication data from secrets after bean construction.
     */
    @PostConstruct
    public void initializeSecrets() {
        try {
            // Load API key from Secret Manager
            this.apiKey = appProperties.getSecrets().getApiKey();
            logger.info("API key loaded from Secret Manager");
            
            // Load JWT secret from Secret Manager  
            this.jwtSecret = appProperties.getSecrets().getJwtSecret();
            logger.info("JWT secret loaded from Secret Manager");
            
            // Load user passwords from Secret Manager
            // In a real application, you might have individual secrets for each user
            loadUserPasswords();
            
            logger.info("Authentication service initialized with {} users", userPasswords.size());
            
        } catch (Exception e) {
            logger.error("Failed to initialize authentication secrets", e);
            throw new RuntimeException("Authentication service initialization failed", e);
        }
    }
    
    /**
     * Authenticate a user with username and password.
     * 
     * @param username The username
     * @param password The plain text password
     * @return true if authentication successful, false otherwise
     */
    public boolean authenticateUser(String username, String password) {
        try {
            String storedPasswordHash = userPasswords.get(username);
            if (storedPasswordHash == null) {
                logger.warn("Authentication failed: user not found: {}", username);
                return false;
            }
            
            boolean isValid = passwordEncoder.matches(password, storedPasswordHash);
            if (isValid) {
                logger.info("User authenticated successfully: {}", username);
            } else {
                logger.warn("Authentication failed: invalid password for user: {}", username);
            }
            
            return isValid;
            
        } catch (Exception e) {
            logger.error("Authentication error for user: {}", username, e);
            return false;
        }
    }
    
    /**
     * Validate an API key.
     * 
     * @param providedApiKey The API key to validate
     * @return true if valid, false otherwise
     */
    public boolean validateApiKey(String providedApiKey) {
        boolean isValid = apiKey != null && apiKey.equals(providedApiKey);
        if (isValid) {
            logger.info("API key validation successful");
        } else {
            logger.warn("API key validation failed");
        }
        return isValid;
    }
    
    /**
     * Get the JWT secret for token signing/verification.
     * 
     * @return The JWT secret
     */
    public String getJwtSecret() {
        return jwtSecret;
    }
    
    /**
     * Create a new user with password stored in Secret Manager.
     * This is a demo method - in production, you'd have a proper user management system.
     * 
     * @param username The username
     * @param password The plain text password
     */
    public void createUser(String username, String password) {
        String hashedPassword = passwordEncoder.encode(password);
        userPasswords.put(username, hashedPassword);
        
        // In a real application, you might store this in Secret Manager
        // secretManagerService.storeKeyValueSecret("user-" + username + "-password", hashedPassword);
        
        logger.info("User created: {}", username);
    }
    
    /**
     * Load user passwords from Secret Manager.
     * This demonstrates how you might load multiple user credentials.
     */
    private void loadUserPasswords() {
        try {
            // Demo users - in production, you'd have a different approach
            // For demo purposes, we'll create some users with passwords from Secret Manager
            
            // Get the database password and use it as a demo user password
            String dbPassword = appProperties.getSecrets().getDatabasePassword();
            if (dbPassword != null) {
                // Create a demo user with the database password
                createUser("admin", dbPassword);
                createUser("demo", "demo123"); // Hardcoded for demo
            }
            
            // You could also load individual user passwords like this:
            // String userPassword = secretManagerService.getKeyValueSecret("user-john-password");
            // userPasswords.put("john", userPassword);
            
        } catch (Exception e) {
            logger.error("Failed to load user passwords from Secret Manager", e);
            // Create fallback demo users
            createUser("admin", "admin123");
            createUser("demo", "demo123");
        }
    }
    
    /**
     * Get authentication statistics for monitoring.
     * 
     * @return Map containing authentication statistics
     */
    public Map<String, Object> getAuthStats() {
        Map<String, Object> stats = new HashMap<>();
        stats.put("totalUsers", userPasswords.size());
        stats.put("apiKeyConfigured", apiKey != null);
        stats.put("jwtSecretConfigured", jwtSecret != null);
        return stats;
    }
}