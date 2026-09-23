#!/usr/bin/env bash
# realm 초기화 후 T1~T7 을 순서대로 실행하고 결과를 ../results/ 에 저장한다.
# 전제: 루트 docker compose(-p sas-poc) MySQL, keycloak/docker-compose.yml, kc resource-server(:18082) 기동 상태
cd "$(dirname "$0")" || exit 1
OUT=../results
mkdir -p "$OUT"

bash reset.sh || exit 1
total_fail=0
for t in T1-auth T2-2fa T3-refresh T4-logout T5-force-logout T6-login-ui T7-sms-otp; do
	bash "$t.sh" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | tee "$OUT/$t.txt"
	grep -q 'FAIL=0' "$OUT/$t.txt" || total_fail=$((total_fail + 1))
done
echo
grep -H '^결과:' "$OUT"/T*.txt
[ "$total_fail" -eq 0 ]
