package com.example.keycloak.storage;

import java.util.List;

import org.keycloak.component.ComponentModel;
import org.keycloak.models.KeycloakSession;
import org.keycloak.provider.ProviderConfigProperty;
import org.keycloak.provider.ProviderConfigurationBuilder;
import org.keycloak.storage.UserStorageProviderFactory;

public class LegacyUserStorageProviderFactory implements UserStorageProviderFactory<LegacyUserStorageProvider> {

	public static final String PROVIDER_ID = "legacy-mysql";

	@Override
	public LegacyUserStorageProvider create(KeycloakSession session, ComponentModel model) {
		LegacyUserRepository repository = new LegacyUserRepository(
				config(model, "jdbcUrl", "LEGACY_DB_URL"),
				config(model, "dbUser", "LEGACY_DB_USER"),
				config(model, "dbPassword", "LEGACY_DB_PASSWORD"));
		return new LegacyUserStorageProvider(session, model, repository);
	}

	/** Admin Console 컴포넌트 설정값 우선, 없으면 환경변수. */
	private static String config(ComponentModel model, String key, String env) {
		String value = model.get(key);
		return (value == null || value.isBlank()) ? System.getenv(env) : value;
	}

	@Override
	public String getId() {
		return PROVIDER_ID;
	}

	@Override
	public String getHelpText() {
		return "기존 MySQL 회원 테이블(sas_poc.users) 연동";
	}

	@Override
	public List<ProviderConfigProperty> getConfigProperties() {
		return ProviderConfigurationBuilder.create()
				.property().name("jdbcUrl").label("JDBC URL").type(ProviderConfigProperty.STRING_TYPE).add()
				.property().name("dbUser").label("DB User").type(ProviderConfigProperty.STRING_TYPE).add()
				.property().name("dbPassword").label("DB Password").type(ProviderConfigProperty.PASSWORD).add()
				.build();
	}

}
