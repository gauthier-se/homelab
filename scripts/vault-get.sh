#!/usr/bin/env bash
# Read one secret out of OpenBao and print it as JSON.
#
# There is no `bao` CLI in the devshell, and installing one to read four values
# would be the wrong trade. This does the same thing with curl, using the same
# read-only token every play uses.
#
#   ./scripts/vault-get.sh freshrss
#   ./scripts/vault-get.sh freshrss | jq -r .admin_api_password
#
# curl and jq only, on purpose: no python3, so this runs in a plain shell. The
# moment you reach for it is usually the moment something is broken and you are
# not in the devshell.
#
# ⚠️ Prints secrets on stdout. Pipe it, do not leave it in scrollback.
set -euo pipefail

path=${1:?usage: vault-get.sh <path under homelab/>}
secrets=${HOMELAB_SECRETS:-$HOME/.config/homelab}
addr=${OPENBAO_ADDR:-https://10.10.25.10:8200}
ca=${OPENBAO_CA:-$secrets/homelab-root-ca.pem}
token=${OPENBAO_TOKEN:-$(jq -r '.auth.client_token' \
  "$secrets/openbao-ansible-token.json")}

curl -sS --cacert "$ca" -H "X-Vault-Token: $token" \
  "$addr/v1/homelab/data/$path" |
  jq -S '.data.data'
