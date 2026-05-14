package com.example;

import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.bind.annotation.GetMapping;

@RestController
public class InsecureController {

    @GetMapping("/insecure")
    public String insecureEndpoint() {
        return "Insecure";
    }
}
