#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3
# A nix-shell shebang and not `python3`: there is no python3 on the PATH outside
# the devshell, and the moment you reach for this script is rarely the moment
# you are already in it. Same reasoning as writing vault-get.sh in curl and jq,
# reached differently: here the root ceremony is worth keeping in reviewed
# Python rather than a XOR in bash, so the interpreter is what gets brought
# along. Measured cost: 0.5 s on a warm start.
"""Mint a fresh OpenBao root token from the unseal keys, then get out.

The initial root token is revoked: a credential that
opens everything, never expires and lives in a file is not worth the
convenience. Nothing in the IaC needs one -- Ansible reads with `ansible-read`,
the TLS renewal writes one PKI path -- but *creating* a new secret path does,
and that happens a few times a year.

This is that path. It runs the three-step generate-root ceremony over the HTTP
API, because there is no `bao` CLI on this machine.

    ./scripts/vault-generate-root.py            # prompts for 3 keys, no echo
    printf '%s\n' k1 k2 k3 | ./scripts/vault-generate-root.py
    ./scripts/vault-generate-root.py --cancel   # abandon a half-finished attempt

⚠️ The token it prints has no expiry. Use it, then revoke it:

    curl -sS --cacert $HOMELAB_SECRETS/homelab-root-ca.pem \\
      -H "X-Vault-Token: $TOKEN" -X POST \\
      https://10.10.25.10:8200/v1/auth/token/revoke-self
"""
from __future__ import annotations

import argparse
import base64
import getpass
import json
import os
import pathlib
import ssl
import sys
import urllib.error
import urllib.request

SECRETS = pathlib.Path(
    os.environ.get("HOMELAB_SECRETS", pathlib.Path.home() / ".config/homelab")
)
ADDR = os.environ.get("OPENBAO_ADDR", "https://10.10.25.10:8200")
CA = os.environ.get("OPENBAO_CA", str(SECRETS / "homelab-root-ca.pem"))


def api(path: str, body: dict | None = None, method: str | None = None) -> dict:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        f"{ADDR}/v1/{path}",
        data=data,
        headers={"Content-Type": "application/json"},
        method=method or ("POST" if data else "GET"),
    )
    ctx = ssl.create_default_context(cafile=CA)
    with urllib.request.urlopen(req, context=ctx, timeout=15) as r:
        raw = r.read()
    return json.loads(raw) if raw else {}


def decode(encoded: str, otp: str) -> str:
    """XOR the encoded token with the OTP, which is how Vault/OpenBao hands it back.

    Raw base64, no padding: the server encodes with RawStdEncoding, so
    `base64.b64decode` would choke on the missing `=` without the fix-up.
    """
    padded = encoded + "=" * (-len(encoded) % 4)
    token = base64.b64decode(padded)
    return bytes(a ^ b for a, b in zip(token, otp.encode())).decode()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--cancel", action="store_true",
                    help="abandon a pending attempt and exit")
    args = ap.parse_args()

    if args.cancel:
        api("sys/generate-root/attempt", method="DELETE")
        print("attempt cancelled")
        return 0

    status = api("sys/generate-root/attempt")
    if status.get("started"):
        sys.exit("an attempt is already in progress - rerun with --cancel first")

    # Let the server pick the OTP: it knows its own token length, and a
    # hand-rolled one is a way to get the XOR silently wrong.
    start = api("sys/generate-root/attempt", {})
    nonce, otp = start["nonce"], start["otp"]
    needed = start["required"]
    print(f"nonce {nonce} - {needed} keys expected", file=sys.stderr)

    try:
        for i in range(needed):
            if sys.stdin.isatty():
                key = getpass.getpass(f"unseal key {i + 1}/{needed}: ")
            else:
                key = sys.stdin.readline().strip()
            if not key:
                sys.exit("empty key, aborting")
            res = api("sys/generate-root/update", {"key": key, "nonce": nonce})
            if res.get("complete"):
                print(decode(res["encoded_token"], otp))
                print("⚠️  token has no expiry - revoke it after use "
                      "(auth/token/revoke-self)", file=sys.stderr)
                return 0
            print(f"   {res['progress']}/{res['required']}", file=sys.stderr)
        sys.exit("incomplete ceremony")
    except BaseException:
        # Never leave a half-finished attempt behind: it blocks the next one.
        api("sys/generate-root/attempt", method="DELETE")
        raise


if __name__ == "__main__":
    sys.exit(main())
