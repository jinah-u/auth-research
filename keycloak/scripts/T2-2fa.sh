#!/usr/bin/env bash
# T2. 2FA — TOTP(기본 제공, 설정만) / Email OTP(Custom Authenticator SPI) / WebAuthn 제공 여부
source "$(dirname "$0")/lib.sh"
J=$WORK/t2.jar
MAILHOG=http://localhost:8025

wait_next_totp_window() { # 같은 코드 재사용 금지(otpPolicyCodeReusable=false) → 다음 30초 창까지 대기
	local s=$(( 30 - $(date +%s) % 30 + 1 ))
	echo "  다음 TOTP 창까지 ${s}초 대기..."
	sleep "$s"
}

uid=$(user_id kcuser)

log "T2-1 TOTP: kcuser 에 CONFIGURE_TOTP required action 지정 (Admin 설정만, 코드 없음)"
for cred in $(admin GET "/users/$uid/credentials" | node -e "JSON.parse(require('fs').readFileSync(0)).filter(c=>c.type==='otp').forEach(c=>console.log(c.id))"); do
	admin DELETE "/users/$uid/credentials/$cred" >/dev/null
done
admin PUT "/users/$uid" '{"requiredActions":["CONFIGURE_TOTP"]}'
rm -f "$J"; start_login "$J"
submit_form "$J" username=kcuser password=password
follow_kc_redirect "$J"
check "ID/PW 후 OTP 등록 화면 표시" yes "$(page_has 'name="totpSecret"')"
SECRET=$(u totpsecret <"$WORK/page.html")
submit_form "$J" "totp=$(u totp "$SECRET")" "totpSecret=$SECRET" userLabel=demo-authenticator
check "계산한 TOTP 로 등록 → redirect_uri 로 302" 302 "$(status)"
exchange_code "$J"
check "등록과 함께 로그인 완료(토큰 발급)" yes "$([ -n "$ACCESS_TOKEN" ] && echo yes || echo no)"
check "kcuser credential 에 otp 추가됨" yes "$(admin GET "/users/$uid/credentials" | grep -q '"type":"otp"' && echo yes || echo no)"
echo "  acr=$(echo "$ACCESS_TOKEN" | u jwt acr) amr=$(echo "$ACCESS_TOKEN" | u jwt amr)"

log "T2-2 TOTP 등록 사용자의 다음 로그인 (틀린 코드 / 올바른 코드)"
wait_next_totp_window
rm -f "$J"; start_login "$J"
submit_form "$J" username=kcuser password=password
check "ID/PW 후 OTP 입력 화면" yes "$(page_has 'name="otp"')"
submit_form "$J" otp=000000
check "틀린 코드 → OTP 화면 재표시(200)" 200 "$(status)"
check "오류 메시지 표시" yes "$(page_has 'Invalid authenticator code')"
submit_form "$J" "otp=$(u totp "$SECRET")"
check "올바른 코드 → 302" 302 "$(status)"
exchange_code "$J"
check "토큰 발급" yes "$([ -n "$ACCESS_TOKEN" ] && echo yes || echo no)"
r=$(curl -s -u "$CLIENT_ID:$CLIENT_SECRET" -d grant_type=password -d username=kcuser -d password=password "$OIDC/token")
check "Direct Grant(ROPC)에서도 OTP 없으면 거부" invalid_grant "$(echo "$r" | u json error)"
echo "  error_description: $(echo "$r" | u json error_description)"
for cred in $(admin GET "/users/$uid/credentials" | node -e "JSON.parse(require('fs').readFileSync(0)).filter(c=>c.type==='otp').forEach(c=>console.log(c.id))"); do
	admin DELETE "/users/$uid/credentials/$cred" >/dev/null
done
echo "  (정리) kcuser OTP credential 삭제"

log "T2-3 Email OTP (Custom Authenticator SPI) — 기존 MySQL 회원 user 로 테스트"
admin POST "/authentication/flows/browser/copy" '{"newName":"browser-email-otp"}' >/dev/null
admin POST "/authentication/flows/browser-email-otp%20forms/executions/execution" '{"provider":"email-otp"}' >/dev/null
exec_id=$(admin GET "/authentication/flows/browser-email-otp/executions" | node -e "const a=JSON.parse(require('fs').readFileSync(0));console.log(a.find(e=>e.providerId==='email-otp').id)")
admin PUT "/authentication/flows/browser-email-otp/executions" "{\"id\":\"$exec_id\",\"requirement\":\"REQUIRED\"}"
admin POST "/authentication/executions/$exec_id/lower-priority" >/dev/null   # Username Password Form 뒤로
flow_id=$(admin GET "/authentication/flows" | node -e "const a=JSON.parse(require('fs').readFileSync(0));console.log(a.find(f=>f.alias==='browser-email-otp').id)")
cid=$(admin GET "/clients?clientId=$CLIENT_ID" | u json 0.id)
admin PUT "/clients/$cid" "{\"authenticationFlowBindingOverrides\":{\"browser\":\"$flow_id\"}}"
echo "  flow: $(admin GET "/authentication/flows/browser-email-otp/executions" | node -e "const a=JSON.parse(require('fs').readFileSync(0));console.log(a.map(e=>'  '.repeat(e.level)+(e.displayName)+'['+e.requirement+']').join(' > '))")"

curl -s -X DELETE "$MAILHOG/api/v1/messages" >/dev/null
rm -f "$J"; start_login "$J"
submit_form "$J" username=user password=password
check "ID/PW 후 Email OTP 입력 화면" yes "$(page_has 'kc-email-otp-form')"
sleep 1
MAIL_CODE=$(curl -s "$MAILHOG/api/v2/messages" | u mailcode)
echo "  MailHog 수신: to=$(curl -s "$MAILHOG/api/v2/messages" | u json items.0.Raw.To) code=$MAIL_CODE"
check "메일로 6자리 코드 수신" yes "$([ ${#MAIL_CODE} -eq 6 ] && echo yes || echo no)"
submit_form "$J" code=999999
check "틀린 코드 → 폼 재표시(200)" 200 "$(status)"
check "오류 메시지 표시" yes "$(page_has 'Invalid email code')"
submit_form "$J" "code=$MAIL_CODE"
check "올바른 코드 → 302" 302 "$(status)"
exchange_code "$J"
check "토큰 발급 (preferred_username=user)" user "$(echo "$ACCESS_TOKEN" | u jwt preferred_username)"
admin PUT "/clients/$cid" '{"authenticationFlowBindingOverrides":{"browser":""}}'
admin DELETE "/authentication/flows/$flow_id" >/dev/null
echo "  (정리) client flow override 해제, browser-email-otp flow 삭제"

log "T2-4 WebAuthn / Passkey 기본 제공 여부 (Admin API 로 provider 존재만 확인, 실제 등록은 브라우저 필요)"
providers=$(admin GET "/authentication/authenticator-providers")
check "webauthn-authenticator (2FA)" yes "$(echo "$providers" | grep -q '"webauthn-authenticator"' && echo yes || echo no)"
check "webauthn-authenticator-passwordless (Passkey)" yes "$(echo "$providers" | grep -q '"webauthn-authenticator-passwordless"' && echo yes || echo no)"
check "required action webauthn-register" yes "$(admin GET "/authentication/required-actions" | grep -q '"webauthn-register"' && echo yes || echo no)"
echo "  email/sms 계열 기본 authenticator: $(echo "$providers" | node -e "const a=JSON.parse(require('fs').readFileSync(0));console.log(a.filter(p=>/sms|email/i.test(p.id)).map(p=>p.id).join(', ')||'없음')")"

summary
