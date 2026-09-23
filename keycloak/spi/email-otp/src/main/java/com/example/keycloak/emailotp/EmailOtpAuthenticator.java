package com.example.keycloak.emailotp;

import java.security.SecureRandom;

import jakarta.ws.rs.core.MultivaluedMap;
import jakarta.ws.rs.core.Response;
import org.jboss.logging.Logger;
import org.keycloak.authentication.AuthenticationFlowContext;
import org.keycloak.authentication.AuthenticationFlowError;
import org.keycloak.authentication.Authenticator;
import org.keycloak.email.EmailException;
import org.keycloak.email.EmailSenderProvider;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.RealmModel;
import org.keycloak.models.UserModel;
import org.keycloak.sessions.AuthenticationSessionModel;

/**
 * Email OTP 2차 인증 (Custom Authenticator SPI). Keycloak 기본 제공 기능이 아니라 직접 구현한다.
 * 1차 인증(ID/PW) 후 6자리 코드를 메일로 보내고, 입력값을 인증 세션 노트와 비교한다.
 */
public class EmailOtpAuthenticator implements Authenticator {

	static final long TTL_MILLIS = 5 * 60 * 1000L;

	private static final Logger LOG = Logger.getLogger(EmailOtpAuthenticator.class);

	private static final String NOTE_CODE = "email-otp-code";

	private static final String NOTE_EXPIRES = "email-otp-expires";

	private static final String FORM = "email-otp.ftl";

	private static final SecureRandom RANDOM = new SecureRandom();

	@Override
	public void authenticate(AuthenticationFlowContext context) {
		String code = String.format("%06d", RANDOM.nextInt(1_000_000));
		AuthenticationSessionModel authSession = context.getAuthenticationSession();
		authSession.setAuthNote(NOTE_CODE, code);
		authSession.setAuthNote(NOTE_EXPIRES, Long.toString(System.currentTimeMillis() + TTL_MILLIS));

		try {
			send(context.getSession(), context.getRealm(), context.getUser(), code);
		}
		catch (EmailException e) {
			LOG.error("email otp send failed", e);
			context.failureChallenge(AuthenticationFlowError.INTERNAL_ERROR,
					context.form().setError("emailOtpSendFailed").createErrorPage(Response.Status.INTERNAL_SERVER_ERROR));
			return;
		}
		context.challenge(context.form().createForm(FORM));
	}

	@Override
	public void action(AuthenticationFlowContext context) {
		MultivaluedMap<String, String> form = context.getHttpRequest().getDecodedFormParameters();
		String input = form.getFirst("code");
		AuthenticationSessionModel authSession = context.getAuthenticationSession();
		String expected = authSession.getAuthNote(NOTE_CODE);
		String expires = authSession.getAuthNote(NOTE_EXPIRES);

		if (expected == null || expires == null || System.currentTimeMillis() > Long.parseLong(expires)) {
			context.failureChallenge(AuthenticationFlowError.EXPIRED_CODE,
					context.form().setError("emailOtpExpired").createForm(FORM));
			return;
		}
		if (!expected.equals(input)) {
			context.failureChallenge(AuthenticationFlowError.INVALID_CREDENTIALS,
					context.form().setError("emailOtpInvalid").createForm(FORM));
			return;
		}
		authSession.removeAuthNote(NOTE_CODE);
		authSession.removeAuthNote(NOTE_EXPIRES);
		context.success();
	}

	private void send(KeycloakSession session, RealmModel realm, UserModel user, String code) throws EmailException {
		String text = "로그인 인증 코드: " + code + " (5분간 유효)";
		session.getProvider(EmailSenderProvider.class)
				.send(realm.getSmtpConfig(), user, "[demo] 로그인 인증 코드", text, "<p>" + text + "</p>");
	}

	@Override
	public boolean requiresUser() {
		return true;
	}

	@Override
	public boolean configuredFor(KeycloakSession session, RealmModel realm, UserModel user) {
		return user.getEmail() != null;
	}

	@Override
	public void setRequiredActions(KeycloakSession session, RealmModel realm, UserModel user) {
	}

	@Override
	public void close() {
	}

}
