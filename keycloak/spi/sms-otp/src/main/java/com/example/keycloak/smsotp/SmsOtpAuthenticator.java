package com.example.keycloak.smsotp;

import java.security.SecureRandom;

import jakarta.ws.rs.core.MultivaluedMap;
import jakarta.ws.rs.core.Response;
import org.jboss.logging.Logger;
import org.keycloak.authentication.AuthenticationFlowContext;
import org.keycloak.authentication.AuthenticationFlowError;
import org.keycloak.authentication.Authenticator;
import org.keycloak.forms.login.LoginFormsProvider;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.RealmModel;
import org.keycloak.models.UserModel;
import org.keycloak.sessions.AuthenticationSessionModel;

/**
 * SMS OTP 2차 인증 (Custom Authenticator SPI). Keycloak 기본 제공 기능이 아니라 직접 구현한다.
 * 1차 인증(ID/PW) 후 사용자 속성 phoneNumber 로 6자리 코드를 보내고, 입력값을 인증 세션 노트와 비교한다.
 */
public class SmsOtpAuthenticator implements Authenticator {

	public static final String PHONE_ATTRIBUTE = "phoneNumber";

	static final long TTL_MILLIS = 5 * 60 * 1000L;

	private static final Logger LOG = Logger.getLogger(SmsOtpAuthenticator.class);

	private static final String NOTE_CODE = "sms-otp-code";

	private static final String NOTE_EXPIRES = "sms-otp-expires";

	private static final String FORM = "sms-otp.ftl";

	private static final SecureRandom RANDOM = new SecureRandom();

	private final SmsSender sender;

	public SmsOtpAuthenticator(SmsSender sender) {
		this.sender = sender;
	}

	@Override
	public void authenticate(AuthenticationFlowContext context) {
		String phoneNumber = context.getUser().getFirstAttribute(PHONE_ATTRIBUTE);
		String code = String.format("%06d", RANDOM.nextInt(1_000_000));
		AuthenticationSessionModel authSession = context.getAuthenticationSession();
		authSession.setAuthNote(NOTE_CODE, code);
		authSession.setAuthNote(NOTE_EXPIRES, Long.toString(System.currentTimeMillis() + TTL_MILLIS));

		try {
			sender.send(phoneNumber, "[demo] 로그인 인증번호 " + code + " (5분간 유효)");
		}
		catch (SmsSender.SmsException e) {
			LOG.error("sms otp send failed", e);
			context.failureChallenge(AuthenticationFlowError.INTERNAL_ERROR,
					context.form().setError("smsOtpSendFailed").createErrorPage(Response.Status.INTERNAL_SERVER_ERROR));
			return;
		}
		context.challenge(form(context).createForm(FORM));
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
					form(context).setError("smsOtpExpired").createForm(FORM));
			return;
		}
		if (!expected.equals(input)) {
			context.failureChallenge(AuthenticationFlowError.INVALID_CREDENTIALS,
					form(context).setError("smsOtpInvalid").createForm(FORM));
			return;
		}
		authSession.removeAuthNote(NOTE_CODE);
		authSession.removeAuthNote(NOTE_EXPIRES);
		context.success();
	}

	private LoginFormsProvider form(AuthenticationFlowContext context) {
		return context.form().setAttribute("maskedPhone", mask(context.getUser().getFirstAttribute(PHONE_ATTRIBUTE)));
	}

	/** 01012345678 → 010-****-5678 */
	static String mask(String phoneNumber) {
		String digits = phoneNumber == null ? "" : phoneNumber.replaceAll("\\D", "");
		if (digits.length() < 8) {
			return "****";
		}
		return digits.substring(0, 3) + "-****-" + digits.substring(digits.length() - 4);
	}

	@Override
	public boolean requiresUser() {
		return true;
	}

	@Override
	public boolean configuredFor(KeycloakSession session, RealmModel realm, UserModel user) {
		String phoneNumber = user.getFirstAttribute(PHONE_ATTRIBUTE);
		return phoneNumber != null && !phoneNumber.isBlank();
	}

	@Override
	public void setRequiredActions(KeycloakSession session, RealmModel realm, UserModel user) {
	}

	@Override
	public void close() {
	}

}
