package com.example;

import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.security.access.prepost.PreAuthorize;

@RestController
public class SecureController {

    @PreAuthorize("hasRole('USER')")
    @GetMapping("/secure")
    public String secureEndpoint() {
        return "Secure";
    }
}
