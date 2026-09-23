package com.example.keycloak.emailotp;

import java.util.List;

import org.keycloak.Config;
import org.keycloak.authentication.Authenticator;
import org.keycloak.authentication.AuthenticatorFactory;
import org.keycloak.models.AuthenticationExecutionModel;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.KeycloakSessionFactory;
import org.keycloak.provider.ProviderConfigProperty;

public class EmailOtpAuthenticatorFactory implements AuthenticatorFactory {

	public static final String PROVIDER_ID = "email-otp";

	private static final EmailOtpAuthenticator SINGLETON = new EmailOtpAuthenticator();

	private static final AuthenticationExecutionModel.Requirement[] REQUIREMENTS = {
			AuthenticationExecutionModel.Requirement.REQUIRED,
			AuthenticationExecutionModel.Requirement.ALTERNATIVE,
			AuthenticationExecutionModel.Requirement.DISABLED };

	@Override
	public Authenticator create(KeycloakSession session) {
		return SINGLETON;
	}

	@Override
	public String getId() {
		return PROVIDER_ID;
	}

	@Override
	public String getDisplayType() {
		return "Email OTP (demo)";
	}

	@Override
	public String getReferenceCategory() {
		return "otp";
	}

	@Override
	public String getHelpText() {
		return "메일로 6자리 인증 코드를 보내 2차 인증";
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
	public void init(Config.Scope config) {
	}

	@Override
	public void postInit(KeycloakSessionFactory factory) {
	}

	@Override
	public void close() {
	}

}
