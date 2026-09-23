#!/usr/bin/env bash
# T4. 로그아웃 / 토큰 만료 (RP-Initiated Logout, Revocation Endpoint)
source "$(dirname "$0")/lib.sh"
J=$WORK/t4.jar

log "T4-1 RP-Initiated Logout 후 같은 쿠키로 다시 authorize"
rm -f "$J"; login "$J" kcuser password
AT=$ACCESS_TOKEN; RT=$REFRESH_TOKEN; IDT=$ID_TOKEN
check "로그아웃 전: 같은 쿠키로 authorize → 302(SSO로 바로 code 발급)" 302 "$(sso_status "$J")"
curl -s -c "$J" -b "$J" -D "$WORK/headers.txt" -o "$WORK/page.html" \
	"$OIDC/logout?id_token_hint=$IDT&post_logout_redirect_uri=http://127.0.0.1:18080/logged-out"
check "logout endpoint → post_logout_redirect_uri 로 302" 302 "$(status)"
check "로그아웃 후: 같은 쿠키로 authorize → 200(로그인 폼)" 200 "$(sso_status "$J")"

log "T4-2 로그아웃 후 refresh_token"
r=$(refresh "$RT")
check "refresh → invalid_grant" invalid_grant "$(echo "$r" | u json error)"
echo "  error_description: $(echo "$r" | u json error_description)"

log "T4-3 로그아웃 후 이미 발급된 access_token"
check "/api/hello (JWT 로컬 검증) → 여전히 200" 200 "$(api /api/hello "$AT")"
check "/intro/hello (Introspection) → 401" 401 "$(api /intro/hello "$AT")"

log "T4-4 Revocation Endpoint (/revoke)"
rm -f "$J"; login "$J" kcuser password
AT=$ACCESS_TOKEN; RT=$REFRESH_TOKEN
code=$(curl -s -o "$WORK/null" -w '%{http_code}' -u "$CLIENT_ID:$CLIENT_SECRET" \
	-d "token=$RT" -d token_type_hint=refresh_token "$OIDC/revoke")
check "refresh_token revoke" 200 "$code"
r=$(refresh "$RT")
check "revoke 한 refresh_token 사용 → invalid_grant" invalid_grant "$(echo "$r" | u json error)"
echo "  refresh_token revoke 후 access_token: /api=$(api /api/hello "$AT") /intro=$(api /intro/hello "$AT")"
echo "  refresh_token revoke 후 SSO 세션(authorize): $(sso_status "$J") (302=세션 유지, 200=세션 종료)"

rm -f "$J"; login "$J" kcuser password
AT=$ACCESS_TOKEN; RT=$REFRESH_TOKEN
code=$(curl -s -o "$WORK/null" -w '%{http_code}' -u "$CLIENT_ID:$CLIENT_SECRET" \
	-d "token=$AT" -d token_type_hint=access_token "$OIDC/revoke")
check "access_token revoke" 200 "$code"
check "revoke 한 access_token → /api/hello (JWT) 여전히 200" 200 "$(api /api/hello "$AT")"
check "revoke 한 access_token → /intro/hello 401" 401 "$(api /intro/hello "$AT")"
r=$(refresh "$RT")
echo "  access_token revoke 후 refresh_token: $([ -n "$(echo "$r" | u json access_token)" ] && echo '재발급 성공' || echo "$(echo "$r" | u json error)")"

summary
