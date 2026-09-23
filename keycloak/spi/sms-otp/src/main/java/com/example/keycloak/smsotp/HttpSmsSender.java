package com.example.keycloak.smsotp;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;

/**
 * SMS 게이트웨이에 {"to","text"} JSON 을 POST 한다 (keycloak/sms-mock 과 짝).
 */
public class HttpSmsSender implements SmsSender {

	private static final HttpClient CLIENT = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(3)).build();

	private final URI gatewayUri;

	public HttpSmsSender(String gatewayUrl) {
		this.gatewayUri = URI.create(gatewayUrl);
	}

	@Override
	public void send(String phoneNumber, String text) throws SmsException {
		String body = "{\"to\":\"" + escape(phoneNumber) + "\",\"text\":\"" + escape(text) + "\"}";
		HttpRequest request = HttpRequest.newBuilder(gatewayUri)
				.timeout(Duration.ofSeconds(5))
				.header("Content-Type", "application/json; charset=utf-8")
				.POST(HttpRequest.BodyPublishers.ofString(body))
				.build();
		try {
			HttpResponse<String> response = CLIENT.send(request, HttpResponse.BodyHandlers.ofString());
			if (response.statusCode() != 200) {
				throw new SmsException("sms gateway returned " + response.statusCode(), null);
			}
		}
		catch (IOException e) {
			throw new SmsException("sms gateway unreachable", e);
		}
		catch (InterruptedException e) {
			Thread.currentThread().interrupt();
			throw new SmsException("sms send interrupted", e);
		}
	}

	private static String escape(String s) {
		return s.replace("\\", "\\\\").replace("\"", "\\\"");
	}

}
