package com.example.kcresourceserver;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.annotation.Order;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;

/**
 * 같은 Keycloak Access Token을 두 방식으로 검증해 비교한다.
 * /api/** = JWT 로컬 검증, /intro/** = Token Introspection (SAS 데모에서 결론만 확인했던 부분).
 */
@Configuration
public class SecurityConfig {

	@Bean
	@Order(1)
	public SecurityFilterChain jwtSecurityFilterChain(HttpSecurity http) throws Exception {
		http
				.securityMatcher("/api/**")
				.authorizeHttpRequests(auth -> auth.anyRequest().authenticated())
				.sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
				.oauth2ResourceServer(oauth2 -> oauth2.jwt(Customizer.withDefaults()));
		return http.build();
	}

	@Bean
	@Order(2)
	public SecurityFilterChain introspectionSecurityFilterChain(HttpSecurity http) throws Exception {
		http
				.securityMatcher("/intro/**")
				.authorizeHttpRequests(auth -> auth.anyRequest().authenticated())
				.sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
				.oauth2ResourceServer(oauth2 -> oauth2.opaqueToken(Customizer.withDefaults()));
		return http.build();
	}

}
