package com.example.authserver;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.annotation.Order;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.ott.JdbcOneTimeTokenService;
import org.springframework.security.authentication.ott.OneTimeTokenService;
import org.springframework.security.authorization.AuthorizationManager;
import org.springframework.security.authorization.AuthorizationManagerFactories;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.authorization.EnableMultiFactorAuthentication;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.core.authority.FactorGrantedAuthority;
import org.springframework.security.crypto.factory.PasswordEncoderFactories;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.oauth2.server.authorization.JdbcOAuth2AuthorizationService;
import org.springframework.security.oauth2.server.authorization.OAuth2AuthorizationService;
import org.springframework.security.oauth2.server.authorization.client.RegisteredClientRepository;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.access.intercept.RequestAuthorizationContext;
import org.springframework.security.web.authentication.LoginUrlAuthenticationEntryPoint;
import org.springframework.security.web.authentication.ott.OneTimeTokenGenerationSuccessHandler;
import org.springframework.security.web.util.matcher.MediaTypeRequestMatcher;

/**
 * 1차: 비밀번호(FACTOR_PASSWORD), 2차: OTT(FACTOR_OTT) — 리소스 오너가 직접 로그인하는 /oauth2/authorize에만
 * 두 팩터를 모두 요구한다. /oauth2/token 등 클라이언트 자격증명(Basic Auth)으로 호출되는 엔드포인트까지 전역으로
 * MFA를 요구하면(즉 @EnableMultiFactorAuthentication을 앱 전체에 적용하면) 클라이언트 인증 자체가
 * FACTOR_PASSWORD/FACTOR_OTT를 가질 수 없어 403이 발생하므로, MFA는 /oauth2/authorize와 일반 페이지("/")에만
 * 선택적으로 적용한다. OTT 발송은 실제 문자/메일 대신 콘솔 로그로 mock.
 */
// authorities = {}: 전역 AuthorizationManagerFactory(모든 .authenticated()에 MFA 강제)는 등록하지 않고,
// 필터 간 팩터 누적(mfaBeanPostProcessor)만 활성화한다. 전역으로 켜면 클라이언트 인증(Basic Auth)으로
// 호출되는 /oauth2/token 등에도 MFA가 강제되어 403이 발생한다(아래 mfaAuthorizationManager() 주석 참고).
@Configuration
@EnableMultiFactorAuthentication(authorities = {})
public class SecurityConfig {

	// Step 3: 로그인 UI를 auth-server 외부(별도 React 앱, Vite dev server)에 둔다.
	private static final String EXTERNAL_LOGIN_URL = "http://localhost:5180/login";

	@Bean
	@Order(1)
	public SecurityFilterChain authorizationServerSecurityFilterChain(HttpSecurity http) throws Exception {
		AuthorizationManager<RequestAuthorizationContext> mfaAuthenticated = mfaAuthorizationManager();

		http
				.oauth2AuthorizationServer(authorizationServer -> {
					http.securityMatcher(authorizationServer.getEndpointsMatcher());
					authorizationServer.oidc(Customizer.withDefaults());
				})
				.authorizeHttpRequests(authorize -> authorize
						.requestMatchers("/oauth2/authorize").access(mfaAuthenticated)
						.anyRequest().authenticated())
				.exceptionHandling(exceptions -> exceptions
						.defaultAuthenticationEntryPointFor(
								new LoginUrlAuthenticationEntryPoint(EXTERNAL_LOGIN_URL),
								new MediaTypeRequestMatcher(MediaType.TEXT_HTML)));
		return http.build();
	}

	@Bean
	@Order(2)
	public SecurityFilterChain defaultSecurityFilterChain(HttpSecurity http, OneTimeTokenService oneTimeTokenService)
			throws Exception {
		http
				.authorizeHttpRequests(authorize -> authorize.anyRequest().access(mfaAuthorizationManager()))
				.csrf(csrf -> csrf.ignoringRequestMatchers("/login"))
				.formLogin(form -> form
						.loginProcessingUrl("/login")
						.loginPage(EXTERNAL_LOGIN_URL))
				.oneTimeTokenLogin(ott -> ott
						.tokenService(oneTimeTokenService)
						.tokenGenerationSuccessHandler(consoleOttGenerationSuccessHandler()));
		return http.build();
	}

	private AuthorizationManager<RequestAuthorizationContext> mfaAuthorizationManager() {
		return AuthorizationManagerFactories.<RequestAuthorizationContext>multiFactor()
				.requireFactors(FactorGrantedAuthority.PASSWORD_AUTHORITY, FactorGrantedAuthority.OTT_AUTHORITY)
				.build()
				.authenticated();
	}

	@Bean
	public OneTimeTokenGenerationSuccessHandler consoleOttGenerationSuccessHandler() {
		return (request, response, oneTimeToken) -> {
			System.out.printf("%n[MOCK SMS/EMAIL] OTP code for %s: %s (expires: %s)%n%n",
					oneTimeToken.getUsername(), oneTimeToken.getTokenValue(), oneTimeToken.getExpiresAt());
			response.sendRedirect("/login/ott");
		};
	}

	@Bean
	public OneTimeTokenService oneTimeTokenService(JdbcTemplate jdbcTemplate) {
		return new JdbcOneTimeTokenService(jdbcTemplate);
	}

	// Step 6: 인가/토큰 상태를 MySQL(oauth2_authorization 테이블)에 저장 — 관리자가 DB 행을 직접
	// 지워서 특정 사용자의 인가를 강제로 끊을 수 있는지 확인하기 위함.
	@Bean
	public OAuth2AuthorizationService authorizationService(JdbcTemplate jdbcTemplate,
			RegisteredClientRepository registeredClientRepository) {
		return new JdbcOAuth2AuthorizationService(jdbcTemplate, registeredClientRepository);
	}

	@Bean
	public PasswordEncoder passwordEncoder() {
		return PasswordEncoderFactories.createDelegatingPasswordEncoder();
	}

}
