#!/usr/bin/env bash
# T3. refreshToken 동작 (재발급 / rotation 기본값 / rotation ON / 만료 후 복구)
source "$(dirname "$0")/lib.sh"
J=$WORK/t3.jar

log "T3-1 grant_type=refresh_token 재발급"
rm -f "$J"; login "$J" kcuser password
AT0=$ACCESS_TOKEN; RT0=$REFRESH_TOKEN
r=$(refresh "$RT0")
AT1=$(echo "$r" | u json access_token); RT1=$(echo "$r" | u json refresh_token)
check "재발급 성공(access_token 존재)" yes "$([ -n "$AT1" ] && echo yes || echo no)"
check "새 access_token 은 이전과 다름" yes "$([ "$AT0" != "$AT1" ] && echo yes || echo no)"

log "T3-2 기본값(revokeRefreshToken=false): 응답 refresh_token 과 이전 refresh_token 재사용"
check "응답에 새 refresh_token 포함(값이 바뀜)" yes "$([ -n "$RT1" ] && [ "$RT0" != "$RT1" ] && echo yes || echo no)"
r=$(refresh "$RT0")
check "이전 refresh_token(RT0) 재사용 → 여전히 성공" yes "$([ -n "$(echo "$r" | u json access_token)" ] && echo yes || echo no)"
r=$(refresh "$RT0")
check "RT0 3번째 사용도 성공 (재사용 제한 없음)" yes "$([ -n "$(echo "$r" | u json access_token)" ] && echo yes || echo no)"

log "T3-3 rotation ON (revokeRefreshToken=true, refreshTokenMaxReuse=0)"
admin PUT "" '{"revokeRefreshToken":true,"refreshTokenMaxReuse":0}'
rm -f "$J"; login "$J" kcuser password
RT0=$REFRESH_TOKEN
r=$(refresh "$RT0"); RT1=$(echo "$r" | u json refresh_token)
check "RT0 → 재발급 성공, RT1 수령" yes "$([ -n "$RT1" ] && echo yes || echo no)"
r=$(refresh "$RT0")
check "RT0 재사용 → invalid_grant" invalid_grant "$(echo "$r" | u json error)"
echo "  error_description: $(echo "$r" | u json error_description)"
r=$(refresh "$RT1")
check "재사용 감지 후 정상 토큰 RT1 도 거부" invalid_grant "$(echo "$r" | u json error)"
echo "  error_description: $(echo "$r" | u json error_description)"
echo "  이때 SSO 세션(authorize): $(sso_status "$J") (302=세션 유지, 200=세션 종료)"
admin PUT "" '{"revokeRefreshToken":false,"refreshTokenMaxReuse":0}'

log "T3-4 Access Token 만료(20s + Spring 기본 clock skew 60s) → 401 → refresh 로 복구"
rm -f "$J"; login "$J" kcuser password
check "발급 직후 /api/hello" 200 "$(api /api/hello "$ACCESS_TOKEN")"
echo "  82초 대기..."
sleep 82
check "만료 후 /api/hello" 401 "$(api /api/hello "$ACCESS_TOKEN")"
r=$(refresh "$REFRESH_TOKEN")
check "refresh 로 새 토큰 → /api/hello" 200 "$(api /api/hello "$(echo "$r" | u json access_token)")"

summary
