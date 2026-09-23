#!/usr/bin/env bash
# T5. 악의적 세션 강제 종료 (Admin REST API) + Introspection 즉시 차단
source "$(dirname "$0")/lib.sh"
J=$WORK/t5.jar

log "T5-1 Admin REST API 로 특정 세션 강제 종료"
rm -f "$J"; login "$J" kcuser password
AT=$ACCESS_TOKEN; RT=$REFRESH_TOKEN
uid=$(user_id kcuser)
sessions=$(admin GET "/users/$uid/sessions")
sid=$(echo "$ACCESS_TOKEN" | u jwt sid)
echo "  kcuser 활성 세션: $(echo "$sessions" | node -e "const a=JSON.parse(require('fs').readFileSync(0));console.log(a.length+'개 — '+a.map(s=>s.id+' ip='+s.ipAddress+' clients='+Object.values(s.clients).join('/')).join(', '))")"
check "강제 종료 전: authorize → 302" 302 "$(sso_status "$J")"
check "강제 종료 전: /intro/hello" 200 "$(api /intro/hello "$AT")"
code=$(curl -s -o "$WORK/null" -w '%{http_code}' -X DELETE -H "Authorization: Bearer $(admin_token)" "$KC/admin/realms/$REALM/sessions/$sid")
check "DELETE /admin/realms/demo/sessions/{sid}" 204 "$code"
check "강제 종료 후: 같은 쿠키 authorize → 200(로그인 폼)" 200 "$(sso_status "$J")"

log "T5-2 강제 종료 후 refresh_token / access_token (JWT 로컬 검증)"
r=$(refresh "$RT")
check "refresh → invalid_grant" invalid_grant "$(echo "$r" | u json error)"
check "/api/hello (JWT) → 여전히 200 (구조적 한계)" 200 "$(api /api/hello "$AT")"

log "T5-3 같은 access_token 을 Introspection 으로 검증"
check "/intro/hello → 401 (즉시 차단)" 401 "$(api /intro/hello "$AT")"
curl -s -u resource-server:rs-secret -d "token=$AT" "$OIDC/token/introspect" >"$WORK/intro.json"
check "introspect 응답 active" false "$(u json active <"$WORK/intro.json")"

log "T5-4 사용자 단위 / Realm 전체 강제 로그아웃"
Ja=$WORK/t5a.jar; Jb=$WORK/t5b.jar; Jc=$WORK/t5c.jar
rm -f "$Ja" "$Jb" "$Jc"
login "$Ja" kcuser password; ATa=$ACCESS_TOKEN
login "$Jb" kcuser password
login "$Jc" user password; ATc=$ACCESS_TOKEN
echo "  kcuser 세션 수: $(admin GET "/users/$uid/sessions" | u json length)"
code=$(curl -s -o "$WORK/null" -w '%{http_code}' -X POST -H "Authorization: Bearer $(admin_token)" "$KC/admin/realms/$REALM/users/$uid/logout")
check "POST /users/{id}/logout (사용자의 모든 세션 종료)" 204 "$code"
check "kcuser 세션 A → 로그인 폼" 200 "$(sso_status "$Ja")"
check "kcuser 세션 B → 로그인 폼" 200 "$(sso_status "$Jb")"
check "다른 사용자(legacy user) 세션은 유지 → 302" 302 "$(sso_status "$Jc")"
echo "  realm 전체 활성 세션(클라이언트별): $(admin GET '/client-session-stats')"
code=$(curl -s -o "$WORK/null" -w '%{http_code}' -X POST -H "Authorization: Bearer $(admin_token)" "$KC/admin/realms/$REALM/logout-all")
check "POST /logout-all (Realm 전체 세션 종료 + notBefore 갱신)" 200 "$code"
check "legacy user 세션 → 로그인 폼" 200 "$(sso_status "$Jc")"
echo "  logout-all 이후 기존 access_token: /api=$(api /api/hello "$ATc") /intro=$(api /intro/hello "$ATc")"
echo "  realm notBefore: $(admin GET '' | u json notBefore)"

summary
