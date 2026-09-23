package com.example.keycloak.smsotp;

import java.util.List;

import org.keycloak.Config;
import org.keycloak.authentication.Authenticator;
import org.keycloak.authentication.AuthenticatorFactory;
import org.keycloak.models.AuthenticationExecutionModel;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.KeycloakSessionFactory;
import org.keycloak.provider.ProviderConfigProperty;

public class SmsOtpAuthenticatorFactory implements AuthenticatorFactory {

	public static final String PROVIDER_ID = "sms-otp";

	private static final AuthenticationExecutionModel.Requirement[] REQUIREMENTS = {
			AuthenticationExecutionModel.Requirement.REQUIRED,
			AuthenticationExecutionModel.Requirement.ALTERNATIVE,
			AuthenticationExecutionModel.Requirement.DISABLED };

	private SmsOtpAuthenticator authenticator;

	@Override
	public Authenticator create(KeycloakSession session) {
		return authenticator;
	}

	@Override
	public void init(Config.Scope config) {
		String gatewayUrl = System.getenv().getOrDefault("SMS_GATEWAY_URL", "http://localhost:8090/send");
		authenticator = new SmsOtpAuthenticator(new HttpSmsSender(gatewayUrl));
	}

	@Override
	public String getId() {
		return PROVIDER_ID;
	}

	@Override
	public String getDisplayType() {
		return "SMS OTP (demo)";
	}

	@Override
	public String getReferenceCategory() {
		return "otp";
	}

	@Override
	public String getHelpText() {
		return "사용자 속성 phoneNumber 로 6자리 인증번호 문자를 보내 2차 인증";
	}

	@Override
	public boolean isConfigurable() {
		return false;
	}

	@Override
	public AuthenticationExecutionModel.Requirement[] getRequirementChoices() {
		return REQUIREMENTS;
	}

	@Override
	public boolean isUserSetupAllowed() {
		return false;
	}

	@Override
	public List<ProviderConfigProperty> getConfigProperties() {
		return List.of();
	}

	@Override
	public void postInit(KeycloakSessionFactory factory) {
	}

	@Override
	public void close() {
	}

}
