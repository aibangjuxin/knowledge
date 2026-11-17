package com.example.demo.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.client.RestTemplate;

import javax.net.ssl.SSLContext;
import javax.net.ssl.TrustManagerFactory;
import java.security.KeyStore;

@Configuration
public class RestClientConfig {

    /**
     * RestTemplate that uses Java's default TrustStore (cacerts).
     * This is the simplest way to call third-party HTTPS services.
     */
    @Bean
    public RestTemplate restTemplate() {
        return new RestTemplate();
    }

    /**
     * Example: How to explicitly use Java's default cacerts.
     * Usually not needed - Java does this automatically.
     */
    public SSLContext getDefaultSSLContext() throws Exception {
        // Load default TrustStore (Java's cacerts)
        TrustManagerFactory tmf = TrustManagerFactory.getInstance(
                TrustManagerFactory.getDefaultAlgorithm());
        tmf.init((KeyStore) null); // null = use default cacerts

        SSLContext sslContext = SSLContext.getInstance("TLS");
        sslContext.init(null, tmf.getTrustManagers(), null);
        return sslContext;
    }
}
