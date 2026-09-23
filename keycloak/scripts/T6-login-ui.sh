#!/usr/bin/env bash
# T6. 로그인 UI 커스텀 (Theme) / 외부 UI 배치 가능성
source "$(dirname "$0")/lib.sh"
J=$WORK/t6.jar
EXT_ORIGIN=http://localhost:5181   # keycloak/frontend (외부 React UI) 출처

log "T6-1 커스텀 Theme(demo-login) 적용"
admin PUT "" '{"loginTheme":"demo-login"}'
rm -f "$J"; start_login "$J"
check "로그인 페이지에 커스텀 문구" yes "$(page_has '\[DEMO\] Company account sign-in')"
check "로그인 페이지에 커스텀 CSS(demo.css)" yes "$(page_has 'css/demo.css')"
check "커스텀 CSS 파일 서빙" 200 "$(curl -s -o "$WORK/null" -w '%{http_code}' "$KC$(grep -oE '/resources/[^"]+/css/demo.css' "$WORK/page.html" | head -1)")"
submit_form "$J" username=kcuser password=password
check "커스텀 테마에서도 로그인 흐름 동일(302)" 302 "$(status)"
admin PUT "" '{"loginTheme":"keycloak.v2"}'

log "T6-2 외부 UI 에서 Keycloak 로그인 처리 URL 로 직접 POST (SAS 의 loginPage(외부 URL) 방식 재현 시도)"
echo "  (전제) Keycloak 에는 SAS 의 formLogin().loginPage(외부URL) 같은 '미인증 시 외부 로그인 페이지로 redirect' 설정이 없다."
code=$(curl -s -o "$WORK/page.html" -w '%{http_code}' --data-urlencode username=kcuser --data-urlencode password=password \
	"$KC/realms/$REALM/login-actions/authenticate?client_id=$CLIENT_ID")
check "(a) session_code/쿠키 없이 POST → 로그인 실패" yes "$([ "$code" != 302 ] && echo yes || echo no)"
echo "      HTTP $code, 화면 메시지: $(grep -oE 'kc-error-message|id="kc-page-title"[^<]*' "$WORK/page.html" | head -1) / $(grep -oE '(Cookie not found|Page has expired|invalid|expired)[^<]*' "$WORK/page.html" | head -1)"

rm -f "$J"; start_login "$J"
action=$(u formaction <"$WORK/page.html")
code=$(curl -s -o "$WORK/page.html" -w '%{http_code}' --data-urlencode username=kcuser --data-urlencode password=password "$action")
check "(b) 올바른 action URL 이라도 Keycloak 쿠키(AUTH_SESSION_ID) 없이 POST → 실패" yes "$([ "$code" != 302 ] && echo yes || echo no)"
echo "      HTTP $code, 화면: $(grep -oE 'id="kc-page-title"[^<]*' "$WORK/page.html" | sed 's/.*>\s*//') / $(sed 's/<[^>]*>/\n/g' "$WORK/page.html" | grep -iE 'cookie|expired|restart' | head -1 | tr -s ' ')"

acao=$(curl -s -D - -o "$WORK/null" -H "Origin: $EXT_ORIGIN" \
	"$OIDC/auth?client_id=$CLIENT_ID&response_type=code&scope=openid&redirect_uri=$REDIRECT_URI" | grep -i '^access-control-allow-origin' | tr -d '\r')
check "(c) 외부 출처에서 로그인 페이지 fetch → CORS 허용 헤더 없음(session_code 를 읽을 수 없음)" "" "$acao"

log "T6-3 대안: 외부 UI → Direct Access Grant(ROPC, grant_type=password)"
r=$(curl -s -u "$CLIENT_ID:$CLIENT_SECRET" -d grant_type=password -d scope=openid -d username=kcuser -d password=password "$OIDC/token")
AT=$(echo "$r" | u json access_token)
check "ROPC 로 토큰 발급" yes "$([ -n "$AT" ] && echo yes || echo no)"
check "발급 토큰으로 /api/hello" 200 "$(api /api/hello "$AT")"
uid=$(user_id kcuser)
echo "  ROPC 후 Keycloak 사용자 세션: $(admin GET "/users/$uid/sessions" | u json length)개 (서버 측 세션은 생성됨)"
rm -f "$J"
check "브라우저엔 SSO 쿠키가 없음 → authorize 시 로그인 폼(SSO 불가)" 200 "$(sso_status "$J")"
acao=$(curl -s -D - -o "$WORK/null" -H "Origin: $EXT_ORIGIN" -u "$CLIENT_ID:$CLIENT_SECRET" \
	-d grant_type=password -d username=kcuser -d password=password "$OIDC/token" | grep -i '^access-control-allow-origin' | tr -d '\r')
echo "  외부 출처($EXT_ORIGIN)에서 token endpoint 호출 시 CORS: ${acao:-허용 헤더 없음 → webOrigins 등록 필요, 브라우저에서 client_secret 노출 문제}"

log "T6-4 Theme 안에서 React 사용 (Keycloakify 등) — 문서 기준"
echo "  Keycloak 26 은 로그인 테마를 FreeMarker(.ftl)로 렌더링. React 로 만든 화면도 Keycloakify 로 '테마 JAR'로 빌드해"
echo "  Keycloak 이 서빙하면 사용 가능(로그인 처리 주체는 여전히 Keycloak). 별도 도메인의 독립 SPA 로그인은 공식 지원 아님."

summary
