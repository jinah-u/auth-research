package com.example.resourceserver;

import java.security.Principal;
import java.util.Map;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class HelloController {

	@GetMapping("/api/hello")
	public Map<String, String> hello(Principal principal) {
		return Map.of("message", "hello, " + principal.getName());
	}

}
