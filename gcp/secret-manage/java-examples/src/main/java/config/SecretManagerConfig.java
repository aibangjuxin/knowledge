package config;

import com.google.cloud.secretmanager.v1.SecretManagerServiceClient;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;

import java.io.IOException;

/**
 * Configuration class for GCP Secret Manager and related beans.
 */
@Configuration
public class SecretManagerConfig {
    
    @Value("${gcp.project-id}")
    private String projectId;
    
    /**
     * Creates a SecretManagerServiceClient bean for interacting with GCP Secret Manager.
     * This client will automatically use Application Default Credentials (ADC),
     * which in GKE with Workload Identity will be the bound Google Service Account.
     */
    @Bean
    public SecretManagerServiceClient secretManagerServiceClient() throws IOException {
        return SecretManagerServiceClient.create();
    }
    
    /**
     * Provides the GCP project ID as a bean for dependency injection.
     */
    @Bean
    public String gcpProjectId() {
        return projectId;
    }
    
    /**
     * Password encoder for secure password hashing and verification.
     */
    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder(12);
    }
}