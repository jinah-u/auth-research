package com.example.keycloak.storage;

import java.util.List;
import java.util.Map;
import java.util.stream.Stream;

import org.keycloak.common.util.MultivaluedHashMap;
import org.keycloak.component.ComponentModel;
import org.keycloak.credential.UserCredentialManager;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.RealmModel;
import org.keycloak.models.SubjectCredentialManager;
import org.keycloak.storage.StorageId;
import org.keycloak.storage.adapter.AbstractUserAdapter;

/**
 * 기존 회원을 Keycloak UserModel로 노출하는 읽기 전용 어댑터 (Keycloak DB로 import하지 않음).
 */
public class LegacyUserAdapter extends AbstractUserAdapter {

	private final LegacyUser user;

	public LegacyUserAdapter(KeycloakSession session, RealmModel realm, ComponentModel model, LegacyUser user) {
		super(session, realm, model);
		this.user = user;
		this.storageId = new StorageId(storageProviderModel.getId(), user.username());
	}

	@Override
	public String getUsername() {
		return user.username();
	}

	@Override
	public boolean isEnabled() {
		return user.enabled();
	}

	@Override
	public boolean isEmailVerified() {
		return true;
	}

	@Override
	public String getEmail() {
		// 기존 테이블에 email 컬럼이 없어 데모용 주소를 만든다 (Email OTP 수신용)
		return user.username() + LegacyUserStorageProvider.EMAIL_DOMAIN;
	}

	/**
	 * Keycloak 26 User Profile 은 email/firstName/lastName 을 요구한다. 기존 테이블에 없는 값을 채우지 않으면
	 * 로그인 직후 VERIFY_PROFILE(프로필 입력) 화면으로 빠지고, 읽기 전용 저장소라 저장도 불가하다.
	 */
	@Override
	public Map<String, List<String>> getAttributes() {
		MultivaluedHashMap<String, String> attributes = new MultivaluedHashMap<>();
		attributes.add(USERNAME, getUsername());
		attributes.add(EMAIL, getEmail());
		attributes.add(FIRST_NAME, user.username());
		attributes.add(LAST_NAME, "legacy");
		return attributes;
	}

	@Override
	public String getFirstAttribute(String name) {
		List<String> values = getAttributes().get(name);
		return (values == null || values.isEmpty()) ? null : values.get(0);
	}

	@Override
	public Stream<String> getAttributeStream(String name) {
		List<String> values = getAttributes().get(name);
		return values == null ? Stream.empty() : values.stream();
	}

	/** 읽기 전용 저장소라 required action 을 저장할 곳이 없다. 기본 구현은 ReadOnlyException 으로 로그인이 실패한다. */
	@Override
	public Stream<String> getRequiredActionsStream() {
		return Stream.empty();
	}

	@Override
	public void addRequiredAction(String action) {
	}

	@Override
	public void removeRequiredAction(String action) {
	}

	@Override
	public SubjectCredentialManager credentialManager() {
		return new UserCredentialManager(session, realm, this);
	}

}
