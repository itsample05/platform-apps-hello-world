package com.example.helloworld;

import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class HelloWorldController {
    @GetMapping("/")
    Map<String, String> hello() {
        return Map.of("message", "Hello World!");
    }
}
