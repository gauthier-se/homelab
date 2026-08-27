#!/usr/bin/env bash
# Renew the periodic OpenBao tokens this machine holds.
#
# ⚠️ "Periodic" means renewable forever and dead the moment nobody renews. When
# they expire, every play that reads a secret fails and the dashboard role
# silently strips its widgets. Renewing resets the TTL server-side and rewrites
# nothing on disk: the token string is unchanged, only its expiry moves.
#
#   ./scripts/vault-renew-tokens.sh          # renew and report
#   ./scripts/vault-renew-tokens.sh --check  # report only, exit 1 if any is short
#
# Run from launchd weekly,
set -euo pipefail

secrets=${HOMELAB_SECRETS:-$HOME/.config/homelab}
addr=${OPENBAO_ADDR:-https://10.10.25.10:8200}
ca="$secrets/homelab-root-ca.pem"
check_only=0
[ "${1:-}" = "--check" ] && check_only=1

# Ten days: enough warning to act on a laptop that is not opened every day.
warn_below=$((10 * 86400))
status=0

for name in ansible tls; do
  file="$secrets/openbao-$name-token.json"
  if [ ! -r "$file" ]; then
    printf '%-8s absent (%s)\n' "$name" "$file"
    status=1
    continue
  fi
  token=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['auth']['client_token'])" "$file")

  if [ "$check_only" = 0 ]; then
    curl -sS -f --cacert "$ca" -H "X-Vault-Token: $token" \
      -X POST "$addr/v1/auth/token/renew-self" -d '{}' >/dev/null
  fi

  ttl=$(curl -sS -f --cacert "$ca" -H "X-Vault-Token: $token" \
    "$addr/v1/auth/token/lookup-self" |
    python3 -c 'import json,sys;print(json.load(sys.stdin)["data"]["ttl"])')

  printf '%-8s %s jours restants\n' "$name" "$((ttl / 86400))"
  [ "$ttl" -lt "$warn_below" ] && status=1
done

exit "$status"
