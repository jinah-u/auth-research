#!/usr/bin/env bash
# T1. 인증/인가 방식 + 기존 MySQL 회원 연동(User Storage SPI)
source "$(dirname "$0")/lib.sh"
J=$WORK/t1.jar; rm -f "$J"

log "T1-1 Authorization Code + PKCE 토큰 발급 (Keycloak 로컬 사용자 kcuser)"
start_login "$J"
check "authorize → 로그인 폼" 200 "$(status)"
submit_form "$J" username=kcuser password=password
check "ID/PW 제출 → redirect_uri 로 302" 302 "$(status)"
echo "  Location: $(location | cut -c1-110)..."
grep -i '^set-cookie:' "$WORK/headers.txt" | tr -d '\r' | sed 's/=[^;]*;/=<값>;/' | sed 's/^/  /'
exchange_code "$J"
check "access_token 발급" yes "$([ -n "$ACCESS_TOKEN" ] && echo yes || echo no)"
check "refresh_token 발급" yes "$([ -n "$REFRESH_TOKEN" ] && echo yes || echo no)"
check "id_token 발급(openid)" yes "$([ -n "$ID_TOKEN" ] && echo yes || echo no)"
echo "  access_token: typ=$(echo "$ACCESS_TOKEN" | u jwt typ) exp-iat=$(( $(echo "$ACCESS_TOKEN" | u jwt exp) - $(echo "$ACCESS_TOKEN" | u jwt iat) ))s aud=$(echo "$ACCESS_TOKEN" | u jwt aud) sid=$(echo "$ACCESS_TOKEN" | u jwt sid)"
echo "  token 응답: expires_in=$(u json expires_in <"$WORK/token.json") refresh_expires_in=$(u json refresh_expires_in <"$WORK/token.json")"

log "T1-2 Keycloak 가 브라우저에 남기는 쿠키 (cookie jar)"
# Netscape cookie jar: HttpOnly 쿠키는 "#HttpOnly_" 접두어가 붙은 줄로 저장된다
grep -E '^#HttpOnly_|^[^#]' "$J" | awk -F'\t' '{print "  " $6 "  (path=" $3 ", secure=" $4 ", httpOnly=" ($1 ~ /^#HttpOnly_/ ? "Y" : "N") ")"}'

log "T1-3 Resource Server 의 JWT 로컬 검증 (요청마다 Keycloak 조회 여부)"
api /api/hello "$ACCESS_TOKEN" >/dev/null  # 워밍업: realm 재import 시 kid 가 바뀌면 JWKS 1회 재조회
sleep 1
since=$(date -u +%Y-%m-%dT%H:%M:%SZ)
sleep 1
for i in 1 2 3 4 5; do code=$(api /api/hello "$ACCESS_TOKEN"); done
check "/api/hello (JWT) 5회 호출" 200 "$code"
cat "$WORK/api.json"; echo
kc_hits=$(docker logs --since "$since" kc-poc-keycloak 2>&1 | grep -c 'access-log' || true)
echo "  호출 중 Keycloak 액세스 로그 건수: $kc_hits (JWKS 는 최초/새 kid 일 때만 조회, 이후 캐시)"
check "JWT 검증 시 Keycloak 미조회" 0 "$kc_hits"

log "T1-4 기존 MySQL(sas_poc.users) 회원으로 로그인 — User Storage SPI"
J2=$WORK/t1-legacy.jar; rm -f "$J2"
login "$J2" user password
check "legacy user/password 로그인 → 토큰 발급" yes "$([ -n "$ACCESS_TOKEN" ] && echo yes || echo no)"
echo "  preferred_username=$(echo "$ACCESS_TOKEN" | u jwt preferred_username) sub=$(echo "$ACCESS_TOKEN" | u jwt sub)"
check "/api/hello 호출" 200 "$(api /api/hello "$ACCESS_TOKEN")"
rm -f "$J2"; start_login "$J2"; submit_form "$J2" username=user password=wrong
check "틀린 비밀번호 → 로그인 폼 재표시(코드 미발급)" 200 "$(status)"
kc_user_rows=$(docker exec kc-poc-postgres psql -U keycloak -tAc "select count(*) from user_entity where username='user'")
kc_cred_rows=$(docker exec kc-poc-postgres psql -U keycloak -tAc "select count(*) from credential c join user_entity u on c.user_id=u.id where u.username='user'")
check "Keycloak DB(user_entity)에 legacy 사용자 행 없음(import 안 함)" 0 "$kc_user_rows"
check "Keycloak DB(credential)에 legacy 비밀번호 없음" 0 "$kc_cred_rows"
echo "  admin 검색 결과: $(admin GET '/users?search=user' | node -e "const a=JSON.parse(require('fs').readFileSync(0));console.log(a.map(x=>x.username+'(federationLink='+(x.federationLink?'Y':'N')+')').join(', '))")"

log "T1-5 SPI 개발 분량"
spi=$(cd "$SCRIPT_DIR/../spi/user-storage-mysql/src" && find . -name '*.java' | wc -l)
loc=$(cd "$SCRIPT_DIR/../spi/user-storage-mysql/src" && cat $(find . -name '*.java') | grep -cvE '^\s*$')
echo "  user-storage-mysql: Java $spi 파일, 비어있지 않은 라인 $loc"
echo "  배포: ./gradlew providers → build/providers/*.jar (SPI + mysql-connector-j + jbcrypt) → /opt/keycloak/providers 마운트 → 재기동"

summary
