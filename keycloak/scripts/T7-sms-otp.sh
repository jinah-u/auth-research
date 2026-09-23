#!/usr/bin/env bash
# T7. 2FA — SMS(문자) OTP (Custom Authenticator SPI + Mock SMS 게이트웨이)
#   --keep : 정리하지 않고 account-console 에도 flow 를 적용해 둔다 (브라우저 수동 테스트용, 끝나면 reset.sh)
source "$(dirname "$0")/lib.sh"
J=$WORK/t7.jar
SMS=http://localhost:8090
PHONE=01012345678
KEEP=${1:-}

js() { node -e "const d=JSON.parse(require('fs').readFileSync(0));$1"; }

uid=$(user_id kcuser)

log "준비: User Profile 에 phoneNumber 속성 선언 → kcuser 번호 등록 → SMS OTP flow 를 demo-client 에 적용"
profile=$(admin GET "/users/profile" | js "if(!d.attributes.some(a=>a.name==='phoneNumber'))d.attributes.push({name:'phoneNumber',displayName:'Phone number',permissions:{view:['admin','user'],edit:['admin']},multivalued:false});process.stdout.write(JSON.stringify(d))")
admin PUT "/users/profile" "$profile" >/dev/null
user=$(admin GET "/users/$uid" | js "d.attributes=Object.assign(d.attributes||{},{phoneNumber:['$PHONE']});process.stdout.write(JSON.stringify(d))")
admin PUT "/users/$uid" "$user"
check "kcuser phoneNumber 저장됨" "$PHONE" "$(admin GET "/users/$uid" | u json attributes.phoneNumber.0)"

admin POST "/authentication/flows/browser/copy" '{"newName":"browser-sms-otp"}' >/dev/null
admin POST "/authentication/flows/browser-sms-otp%20forms/executions/execution" '{"provider":"sms-otp"}' >/dev/null
exec_id=$(admin GET "/authentication/flows/browser-sms-otp/executions" | js "console.log(d.find(e=>e.providerId==='sms-otp').id)")
admin PUT "/authentication/flows/browser-sms-otp/executions" "{\"id\":\"$exec_id\",\"requirement\":\"REQUIRED\"}"
admin POST "/authentication/executions/$exec_id/lower-priority" >/dev/null   # Username Password Form 뒤로
flow_id=$(admin GET "/authentication/flows" | js "console.log(d.find(f=>f.alias==='browser-sms-otp').id)")
cid=$(admin GET "/clients?clientId=$CLIENT_ID" | u json 0.id)
admin PUT "/clients/$cid" "{\"authenticationFlowBindingOverrides\":{\"browser\":\"$flow_id\"}}"
echo "  forms 하위: $(admin GET "/authentication/flows/browser-sms-otp/executions" | js "console.log(d.filter(e=>e.level===1).map(e=>e.displayName+'['+e.requirement+']').join(' > '))")"

log "T7-1 ID/PW 후 문자 인증번호 입력 화면"
curl -s -X DELETE "$SMS/api/messages" >"$WORK/null"
rm -f "$J"; start_login "$J"
submit_form "$J" username=kcuser password=password
check "SMS OTP 입력 화면 표시" yes "$(page_has 'kc-sms-otp-form')"
check "마스킹된 번호 표시(010-****-5678)" yes "$(page_has '010-\*\*\*\*-5678')"

log "T7-2 Mock SMS 게이트웨이 수신 확인"
msgs=$(curl -s "$SMS/api/messages")
SMS_CODE=$(echo "$msgs" | u smscode)
echo "  수신: to=$(echo "$msgs" | u json 0.to) text=$(echo "$msgs" | u json 0.text)"
check "수신 번호" "$PHONE" "$(echo "$msgs" | u json 0.to)"
check "6자리 인증번호 수신" yes "$([ ${#SMS_CODE} -eq 6 ] && echo yes || echo no)"

log "T7-3 틀린 번호 / 올바른 번호"
submit_form "$J" code=000000
check "틀린 인증번호 → 폼 재표시(200)" 200 "$(status)"
check "오류 메시지 표시" yes "$(page_has 'Invalid SMS code')"
submit_form "$J" "code=$SMS_CODE"
check "올바른 인증번호 → redirect_uri 로 302" 302 "$(status)"
exchange_code "$J"
check "토큰 발급 (preferred_username=kcuser)" kcuser "$(echo "$ACCESS_TOKEN" | u jwt preferred_username)"
check "발급 토큰으로 /api/hello" 200 "$(api /api/hello "$ACCESS_TOKEN")"

log "T7-4 전화번호가 없는 사용자(legacy MySQL 회원 user)"
curl -s -X DELETE "$SMS/api/messages" >"$WORK/null"
rm -f "$J"; start_login "$J"
submit_form "$J" username=user password=password
code=$(status)
check "번호 없는 사용자는 로그인 완료 불가(302 아님)" yes "$([ "$code" != 302 ] && echo yes || echo no)"
echo "  HTTP $code, 화면: $(grep -oE 'id="kc-page-title"[^<]*' "$WORK/page.html" | sed 's/.*>\s*//' | tr -s ' ') / $(sed 's/<[^>]*>/\n/g' "$WORK/page.html" | grep -iE 'error|invalid|credential|contact' | head -1 | tr -s ' ')"
check "문자 미발송" 0 "$(curl -s "$SMS/api/messages" | u json length)"
echo "  → 번호 미등록 사용자를 위한 '번호 등록' required action 은 별도 구현 필요 (Keycloak 기본 없음)"

if [ "$KEEP" = "--keep" ]; then
	acid=$(admin GET "/clients?clientId=account-console" | u json 0.id)
	admin PUT "/clients/$acid" "{\"authenticationFlowBindingOverrides\":{\"browser\":\"$flow_id\"}}"
	echo
	echo "  [--keep] 정리 생략. 브라우저 테스트:"
	echo "    1) http://localhost:8180/realms/demo/account  → kcuser / password"
	echo "    2) http://localhost:8090  (Mock SMS 수신함) 에서 인증번호 확인 후 입력"
	echo "    끝나면: bash $(dirname "$0")/reset.sh"
else
	admin PUT "/clients/$cid" '{"authenticationFlowBindingOverrides":{"browser":""}}'
	admin DELETE "/authentication/flows/$flow_id" >/dev/null
	user=$(admin GET "/users/$uid" | js "delete (d.attributes||{}).phoneNumber;process.stdout.write(JSON.stringify(d))")
	admin PUT "/users/$uid" "$user"
	echo "  (정리) client flow override 해제, browser-sms-otp flow 삭제, kcuser phoneNumber 제거"
fi

summary
