package com.example.keycloak.smsotp;

/**
 * 문자 발송 채널. 데모는 Mock 게이트웨이로 보내고, 실제 업체(NHN Cloud, Naver SENS, Twilio 등)는 이 구현체만 바꾼다.
 */
public interface SmsSender {

	void send(String phoneNumber, String text) throws SmsException;

	class SmsException extends Exception {

		public SmsException(String message, Throwable cause) {
			super(message, cause);
		}

	}

}
