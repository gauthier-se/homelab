#!/bin/sh
# Silences the subscription nags in the PVE web UI. Three edits, all in
# proxmoxlib.js, all idempotent:
#
#   A. the "No valid subscription" modal shown at every login
#   B. the "no-subscription repository is not recommended" banner on the
#      Repositories page, and with it the page-level Warning status, which on an
#      otherwise healthy node is derived from that banner being the only addWarn
#   C. the orange marker and tooltip on the pve-no-subscription row itself
#
# C deliberately keeps the `test` repository warning: an unstable repo is a real
# warning, unlike running the free repository Proxmox itself publishes.
#
# Every proxmox-widget-toolkit upgrade ships a fresh file and reverts all three,
# so /etc/apt/apt.conf.d/99-no-subscription-nag calls this after every apt run.
# Stock file is kept as proxmoxlib.js.orig. Always exits 0: a cosmetic patch
# must never be able to block a package operation.
F=/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
[ -f "$F" ] || exit 0
[ -f "${F}.orig" ] || cp "$F" "${F}.orig"

python3 - "$F" <<'PYEOF' || exit 0
import sys

path = sys.argv[1]
src = open(path, encoding="utf-8").read()

substitutions = [
    # A, login modal
    ("res.data.status.toLowerCase() !== 'active'", "false"),
    # B, Repositories page banner
    ("if (repos.nosubscription) {", "if (false) {"),
    # C, per-row marker, keeping the `test` repo warning intact
    (r"components[0].match(/\w+(-no-subscription|test)\s*$/i)",
     r"components[0].match(/\w+(test)\s*$/i)"),
]

replaced = 0
for old, new in substitutions:
    count = src.count(old)
    if count:
        replaced += count
        src = src.replace(old, new)

if replaced:
    open(path, "w", encoding="utf-8").write(src)

print("patched", replaced)
PYEOF

exit 0
