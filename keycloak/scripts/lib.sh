#!/usr/bin/env bash
# 공통 함수. 각 T*.sh 에서 source 한다.
set -u

KC=http://localhost:8180
REALM=demo
OIDC=$KC/realms/$REALM/protocol/openid-connect
RS=http://localhost:18082
CLIENT_ID=demo-client
CLIENT_SECRET=secret
REDIRECT_URI=http://127.0.0.1:18080/authorized

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WORK=${WORK:-$SCRIPT_DIR/.work}
mkdir -p "$WORK"

PASS=0
FAIL=0

u() { node "$SCRIPT_DIR/util.js" "$@"; }

log() { printf '\n\033[1m== %s\033[0m\n' "$*"; }

check() { # check <설명> <기대값> <실제값>
	if [ "$2" = "$3" ]; then
		PASS=$((PASS + 1)); printf '  [PASS] %s (=%s)\n' "$1" "$3"
	else
		FAIL=$((FAIL + 1)); printf '  [FAIL] %s (expected=%s actual=%s)\n' "$1" "$2" "$3"
	fi
}

summary() { printf '\n결과: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"; [ "$FAIL" -eq 0 ]; }

# --- Admin REST API ---
admin_token() {
	curl -s -d grant_type=password -d client_id=admin-cli -d username=admin -d password=admin \
		"$KC/realms/master/protocol/openid-connect/token" | u json access_token
}

admin() { # admin <METHOD> <path under /admin/realms/demo> [json body]
	local method=$1 path=$2 body=${3:-}
	local token; token=$(admin_token)
	if [ -n "$body" ]; then
		curl -s -X "$method" -H "Authorization: Bearer $token" -H 'Content-Type: application/json' \
			-d "$body" "$KC/admin/realms/$REALM$path"
	else
		curl -s -X "$method" -H "Authorization: Bearer $token" "$KC/admin/realms/$REALM$path"
	fi
}

user_id() { admin GET "/users?username=$1&exact=true" | u json 0.id; }

# --- Authorization Code + PKCE 로그인 ---
# start_login <jar>                  → authorize 요청, 로그인 폼 HTML을 $WORK/page.html 에 저장
# submit_form <jar> <k=v>...         → 현재 페이지 form action 으로 POST, 결과를 page.html / 헤더를 headers.txt 에
# exchange_code <jar>                → Location 의 code 를 토큰으로 교환, $WORK/token.json
start_login() {
	local jar=$1
	read -r VERIFIER CHALLENGE <<<"$(u pkce)"
	echo "$VERIFIER" >"$WORK/verifier"
	curl -s -c "$jar" -b "$jar" -D "$WORK/headers.txt" -o "$WORK/page.html" \
		"$OIDC/auth?client_id=$CLIENT_ID&response_type=code&scope=openid&state=s1&redirect_uri=$REDIRECT_URI&code_challenge=$CHALLENGE&code_challenge_method=S256"
}

submit_form() {
	local jar=$1; shift
	local action; action=$(u formaction <"$WORK/page.html")
	local args=()
	for kv in "$@"; do args+=(--data-urlencode "$kv"); done
	curl -s -c "$jar" -b "$jar" -D "$WORK/headers.txt" -o "$WORK/page.html" "${args[@]}" "$action"
}

status() { head -1 "$WORK/headers.txt" | awk '{print $2}'; }

location() { grep -i '^location:' "$WORK/headers.txt" | tr -d '\r' | cut -d' ' -f2-; }

# 로그인 후 required action(OTP 등록 등) 화면으로 302 되면 따라가서 page.html 에 저장
follow_kc_redirect() {
	local loc; loc=$(location)
	case "$loc" in
	"$KC"/*) curl -s -c "$1" -b "$1" -D "$WORK/headers.txt" -o "$WORK/page.html" "$loc" ;;
	esac
}

page_has() { grep -q "$1" "$WORK/page.html" && echo yes || echo no; }

exchange_code() {
	local code; code=$(location | sed -n 's/.*[?&]code=\([^&]*\).*/\1/p')
	curl -s -u "$CLIENT_ID:$CLIENT_SECRET" -d grant_type=authorization_code -d "code=$code" \
		-d "redirect_uri=$REDIRECT_URI" -d "code_verifier=$(cat "$WORK/verifier")" "$OIDC/token" >"$WORK/token.json"
	ACCESS_TOKEN=$(u json access_token <"$WORK/token.json")
	REFRESH_TOKEN=$(u json refresh_token <"$WORK/token.json")
	ID_TOKEN=$(u json id_token <"$WORK/token.json")
}

# login <jar> <username> <password>  → ID/PW만 있는 기본 흐름 전체
login() {
	start_login "$1"
	submit_form "$1" "username=$2" "password=$3"
	exchange_code "$1"
}

refresh() { # refresh <refresh_token> → 응답 JSON
	curl -s -u "$CLIENT_ID:$CLIENT_SECRET" -d grant_type=refresh_token -d "refresh_token=$1" "$OIDC/token"
}

api() { # api <path> <access_token> → HTTP 상태코드
	curl -s -o "$WORK/api.json" -w '%{http_code}' -H "Authorization: Bearer $2" "$RS$1"
}

# 같은 쿠키로 다시 authorize 했을 때: 302(code 발급 = SSO 세션 살아있음) / 200(로그인 폼 = 세션 없음)
sso_status() {
	start_login "$1"
	status
}
