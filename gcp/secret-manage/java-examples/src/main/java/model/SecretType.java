package model;

/**
 * Enumeration representing different types of secrets that can be stored
 * in GCP Secret Manager.
 */
public enum SecretType {
    /**
     * Simple key-value secrets (strings, passwords, API keys)
     */
    KEY_VALUE,
    
    /**
     * File-based secrets (certificates, keystores, binary files)
     * These are typically Base64 encoded when stored
     */
    FILE_BASED
}