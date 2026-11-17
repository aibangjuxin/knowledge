package config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

import java.util.Map;

/**
 * Configuration properties for the application, including secret configurations.
 */
@Component
@ConfigurationProperties(prefix = "app")
public class AppProperties {
    
    private Secrets secrets = new Secrets();
    private SecretFiles secretFiles = new SecretFiles();
    
    public Secrets getSecrets() {
        return secrets;
    }
    
    public void setSecrets(Secrets secrets) {
        this.secrets = secrets;
    }
    
    public SecretFiles getSecretFiles() {
        return secretFiles;
    }
    
    public void setSecretFiles(SecretFiles secretFiles) {
        this.secretFiles = secretFiles;
    }
    
    /**
     * Configuration for key-value secrets that are injected directly from Secret Manager
     */
    public static class Secrets {
        private String databasePassword;
        private String apiKey;
        private String jwtSecret;
        private String keystoreFile;
        private String sslCertificate;
        
        // Getters and setters
        public String getDatabasePassword() {
            return databasePassword;
        }
        
        public void setDatabasePassword(String databasePassword) {
            this.databasePassword = databasePassword;
        }
        
        public String getApiKey() {
            return apiKey;
        }
        
        public void setApiKey(String apiKey) {
            this.apiKey = apiKey;
        }
        
        public String getJwtSecret() {
            return jwtSecret;
        }
        
        public void setJwtSecret(String jwtSecret) {
            this.jwtSecret = jwtSecret;
        }
        
        public String getKeystoreFile() {
            return keystoreFile;
        }
        
        public void setKeystoreFile(String keystoreFile) {
            this.keystoreFile = keystoreFile;
        }
        
        public String getSslCertificate() {
            return sslCertificate;
        }
        
        public void setSslCertificate(String sslCertificate) {
            this.sslCertificate = sslCertificate;
        }
    }
    
    /**
     * Configuration for file paths where file-based secrets will be written
     */
    public static class SecretFiles {
        private String keystorePath;
        private String sslCertPath;
        
        public String getKeystorePath() {
            return keystorePath;
        }
        
        public void setKeystorePath(String keystorePath) {
            this.keystorePath = keystorePath;
        }
        
        public String getSslCertPath() {
            return sslCertPath;
        }
        
        public void setSslCertPath(String sslCertPath) {
            this.sslCertPath = sslCertPath;
        }
    }
}