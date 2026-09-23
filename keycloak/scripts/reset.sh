#!/usr/bin/env bash
# demo realm 을 삭제하고 Keycloak 을 재기동해 realm/demo-realm.json 을 다시 import 한다.
source "$(dirname "$0")/lib.sh"

log "demo realm 삭제 후 재import"
token=$(admin_token)
curl -s -o "$WORK/null" -X DELETE -H "Authorization: Bearer $token" "$KC/admin/realms/$REALM" || true
docker restart kc-poc-keycloak >/dev/null
for _ in $(seq 1 60); do
	curl -sf "$KC/realms/$REALM/.well-known/openid-configuration" >/dev/null && { echo "ready"; exit 0; }
	sleep 3
done
echo "keycloak not ready" >&2
exit 1
