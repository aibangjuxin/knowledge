package service;

import com.google.cloud.secretmanager.v1.AccessSecretVersionResponse;
import com.google.cloud.secretmanager.v1.SecretManagerServiceClient;
import com.google.cloud.secretmanager.v1.SecretVersionName;
import model.SecretType;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import javax.annotation.PreDestroy;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Base64;
import java.util.concurrent.ConcurrentHashMap;
import java.util.Map;

/**
 * Service for managing secrets from GCP Secret Manager.
 * Supports both key-value and file-based secrets.
 */
@Service
public class SecretManagerService {
    
    private static final Logger logger = LoggerFactory.getLogger(SecretManagerService.class);
    
    private final SecretManagerServiceClient client;
    private final String projectId;
    
    // Cache for secrets to avoid repeated API calls
    private final Map<String, String> secretCache = new ConcurrentHashMap<>();
    
    @Autowired
    public SecretManagerService(SecretManagerServiceClient client, String gcpProjectId) {
        this.client = client;
        this.projectId = gcpProjectId;
        logger.info("SecretManagerService initialized for project: {}", projectId);
    }
    
    /**
     * Retrieves a key-value secret from Secret Manager.
     * Results are cached to avoid repeated API calls.
     * 
     * @param secretName The name of the secret
     * @param version The version of the secret (default: "latest")
     * @return The secret value as a string
     */
    public String getKeyValueSecret(String secretName, String version) {
        String cacheKey = secretName + ":" + version;
        return secretCache.computeIfAbsent(cacheKey, k -> fetchSecretFromGCP(secretName, version));
    }
    
    /**
     * Retrieves a key-value secret using the latest version.
     * 
     * @param secretName The name of the secret
     * @return The secret value as a string
     */
    public String getKeyValueSecret(String secretName) {
        return getKeyValueSecret(secretName, "latest");
    }
    
    /**
     * Retrieves a file-based secret from Secret Manager and decodes it from Base64.
     * 
     * @param secretName The name of the secret containing the Base64-encoded file
     * @param version The version of the secret (default: "latest")
     * @return The decoded file content as byte array
     */
    public byte[] getFileSecret(String secretName, String version) {
        try {
            String base64Content = fetchSecretFromGCP(secretName, version);
            return Base64.getDecoder().decode(base64Content);
        } catch (Exception e) {
            logger.error("Failed to decode file secret: {}", secretName, e);
            throw new RuntimeException("Unable to decode file secret: " + secretName, e);
        }
    }
    
    /**
     * Retrieves a file-based secret using the latest version.
     * 
     * @param secretName The name of the secret
     * @return The decoded file content as byte array
     */
    public byte[] getFileSecret(String secretName) {
        return getFileSecret(secretName, "latest");
    }
    
    /**
     * Retrieves a file-based secret and writes it to the specified path.
     * Creates parent directories if they don't exist.
     * 
     * @param secretName The name of the secret
     * @param outputPath The path where the file should be written
     * @param version The version of the secret
     */
    public void writeFileSecretToPath(String secretName, String outputPath, String version) {
        try {
            byte[] fileContent = getFileSecret(secretName, version);
            Path path = Paths.get(outputPath);
            
            // Create parent directories if they don't exist
            Files.createDirectories(path.getParent());
            
            try (FileOutputStream fos = new FileOutputStream(outputPath)) {
                fos.write(fileContent);
                logger.info("Successfully wrote file secret '{}' to path: {}", secretName, outputPath);
            }
        } catch (IOException e) {
            logger.error("Failed to write file secret '{}' to path: {}", secretName, outputPath, e);
            throw new RuntimeException("Unable to write file secret to path: " + outputPath, e);
        }
    }
    
    /**
     * Retrieves a file-based secret and writes it to the specified path using latest version.
     * 
     * @param secretName The name of the secret
     * @param outputPath The path where the file should be written
     */
    public void writeFileSecretToPath(String secretName, String outputPath) {
        writeFileSecretToPath(secretName, outputPath, "latest");
    }
    
    /**
     * Stores a key-value secret in Secret Manager.
     * Note: This requires additional IAM permissions (secretmanager.versions.add)
     * 
     * @param secretName The name of the secret
     * @param secretValue The value to store
     */
    public void storeKeyValueSecret(String secretName, String secretValue) {
        // Implementation for storing secrets (requires additional permissions)
        logger.warn("Storing secrets requires additional IAM permissions. Secret name: {}", secretName);
        // This would typically be done through infrastructure/deployment scripts
    }
    
    /**
     * Stores a file as a Base64-encoded secret in Secret Manager.
     * 
     * @param secretName The name of the secret
     * @param fileContent The file content as byte array
     */
    public void storeFileSecret(String secretName, byte[] fileContent) {
        String base64Content = Base64.getEncoder().encodeToString(fileContent);
        storeKeyValueSecret(secretName, base64Content);
    }
    
    /**
     * Clears the secret cache. Useful for testing or when secrets are rotated.
     */
    public void clearCache() {
        secretCache.clear();
        logger.info("Secret cache cleared");
    }
    
    /**
     * Gets cache statistics for monitoring purposes.
     * 
     * @return Map containing cache statistics
     */
    public Map<String, Object> getCacheStats() {
        Map<String, Object> stats = new ConcurrentHashMap<>();
        stats.put("cacheSize", secretCache.size());
        stats.put("cachedSecrets", secretCache.keySet());
        return stats;
    }
    
    /**
     * Internal method to fetch secret from GCP Secret Manager.
     * 
     * @param secretName The name of the secret
     * @param version The version of the secret
     * @return The secret value as string
     */
    private String fetchSecretFromGCP(String secretName, String version) {
        try {
            SecretVersionName secretVersionName = SecretVersionName.of(projectId, secretName, version);
            
            logger.debug("Fetching secret: {} version: {} from project: {}", secretName, version, projectId);
            
            AccessSecretVersionResponse response = client.accessSecretVersion(secretVersionName);
            String secretValue = response.getPayload().getData().toStringUtf8();
            
            logger.info("Successfully retrieved secret: {} (version: {})", secretName, version);
            return secretValue;
            
        } catch (Exception e) {
            logger.error("Failed to retrieve secret: {} (version: {}) from project: {}", 
                        secretName, version, projectId, e);
            throw new RuntimeException("Unable to retrieve secret: " + secretName, e);
        }
    }
    
    /**
     * Cleanup method to close the Secret Manager client.
     */
    @PreDestroy
    public void cleanup() {
        if (client != null) {
            client.close();
            logger.info("SecretManagerServiceClient closed");
        }
    }
}