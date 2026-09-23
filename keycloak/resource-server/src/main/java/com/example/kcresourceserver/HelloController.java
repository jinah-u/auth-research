package com.example.kcresourceserver;

import java.security.Principal;
import java.util.Map;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class HelloController {

	@GetMapping("/api/hello")
	public Map<String, String> jwtHello(Principal principal) {
		return Map.of("message", "hello, " + principal.getName(), "validation", "jwt-local");
	}

	@GetMapping("/intro/hello")
	public Map<String, String> introspectionHello(Principal principal) {
		return Map.of("message", "hello, " + principal.getName(), "validation", "introspection");
	}

}
