package com.example.keycloak.storage;

import java.util.Map;
import java.util.stream.Stream;

import org.jboss.logging.Logger;
import org.keycloak.component.ComponentModel;
import org.keycloak.credential.CredentialInput;
import org.keycloak.credential.CredentialInputValidator;
import org.keycloak.models.GroupModel;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.RealmModel;
import org.keycloak.models.UserModel;
import org.keycloak.models.credential.PasswordCredentialModel;
import org.keycloak.storage.StorageId;
import org.keycloak.storage.UserStorageProvider;
import org.keycloak.storage.user.UserLookupProvider;
import org.keycloak.storage.user.UserQueryProvider;
import org.mindrot.jbcrypt.BCrypt;

/**
 * 기존 MySQL 회원 테이블을 Keycloak 사용자 저장소로 연결 (User Storage SPI).
 * 비밀번호도 기존 해시({bcrypt}...)로 검증하므로 Keycloak DB에는 비밀번호가 저장되지 않는다.
 */
public class LegacyUserStorageProvider
		implements UserStorageProvider, UserLookupProvider, UserQueryProvider, CredentialInputValidator {

	static final String EMAIL_DOMAIN = "@legacy.local";

	private static final Logger LOG = Logger.getLogger(LegacyUserStorageProvider.class);

	private static final String BCRYPT_PREFIX = "{bcrypt}";

	private final KeycloakSession session;

	private final ComponentModel model;

	private final LegacyUserRepository repository;

	public LegacyUserStorageProvider(KeycloakSession session, ComponentModel model, LegacyUserRepository repository) {
		this.session = session;
		this.model = model;
		this.repository = repository;
	}

	// --- UserLookupProvider ---

	@Override
	public UserModel getUserById(RealmModel realm, String id) {
		return getUserByUsername(realm, StorageId.externalId(id));
	}

	@Override
	public UserModel getUserByUsername(RealmModel realm, String username) {
		return repository.findByUsername(username)
				.map(u -> (UserModel) new LegacyUserAdapter(session, realm, model, u))
				.orElse(null);
	}

	@Override
	public UserModel getUserByEmail(RealmModel realm, String email) {
		if (email == null || !email.endsWith(EMAIL_DOMAIN)) {
			return null;
		}
		return getUserByUsername(realm, email.substring(0, email.length() - EMAIL_DOMAIN.length()));
	}

	// --- UserQueryProvider (Admin Console/REST 사용자 검색용) ---

	@Override
	public Stream<UserModel> searchForUserStream(RealmModel realm, Map<String, String> params, Integer first,
			Integer max) {
		String keyword = params.getOrDefault(UserModel.SEARCH, params.get(UserModel.USERNAME));
		return repository.search(keyword, first == null ? 0 : first, max == null ? 100 : max)
				.stream()
				.map(u -> new LegacyUserAdapter(session, realm, model, u));
	}

	@Override
	public Stream<UserModel> getGroupMembersStream(RealmModel realm, GroupModel group, Integer first, Integer max) {
		return Stream.empty();
	}

	@Override
	public Stream<UserModel> searchForUserByUserAttributeStream(RealmModel realm, String attrName, String attrValue) {
		return Stream.empty();
	}

	@Override
	public int getUsersCount(RealmModel realm) {
		return repository.count();
	}

	// --- CredentialInputValidator ---

	@Override
	public boolean supportsCredentialType(String credentialType) {
		return PasswordCredentialModel.TYPE.equals(credentialType);
	}

	@Override
	public boolean isConfiguredFor(RealmModel realm, UserModel user, String credentialType) {
		return supportsCredentialType(credentialType);
	}

	@Override
	public boolean isValid(RealmModel realm, UserModel user, CredentialInput input) {
		if (!supportsCredentialType(input.getType())) {
			return false;
		}
		return repository.findByUsername(user.getUsername())
				.map(u -> matches(input.getChallengeResponse(), u.passwordHash()))
				.orElse(false);
	}

	private boolean matches(String raw, String stored) {
		if (stored == null || !stored.startsWith(BCRYPT_PREFIX)) {
			LOG.warn("unsupported password hash format for legacy user");
			return false;
		}
		return BCrypt.checkpw(raw, stored.substring(BCRYPT_PREFIX.length()));
	}

	@Override
	public void close() {
	}

}
