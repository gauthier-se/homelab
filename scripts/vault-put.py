#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3
# A nix-shell shebang and not `python3`: there is no python3 on the PATH outside
# the devshell, and the moment you reach for this script is rarely the moment
# you are already in it. Same reasoning as writing vault-get.sh in curl and jq,
# reached differently: here the root ceremony is worth keeping in reviewed
# Python rather than a XOR in bash, so the interpreter is what gets brought
# along. Measured cost: 0.5 s on a warm start.
"""Write one secret into OpenBao, running the root ceremony around it.

The counterpart to vault-get.sh. Reading uses the read-only `ansible` token
every play carries; *writing* a new path needs root, and there is no permanent
root token any more. So creating a secret is a ceremony:
three unseal keys in, a root token minted, the write, and the token revoked on
the way out.

Doing that by hand is three commands and a token you must remember to revoke.
This is the same thing with the revoke in a `finally`, so an interrupted run
does not leave a credential that opens everything lying around.

    ./scripts/vault-put.py offsite r2_endpoint r2_bucket \
        r2_access_key_id:secret r2_secret_access_key:secret restic_password:secret

Every field is prompted for. A name suffixed with `:secret` is read without echo;
the others are read normally, because an endpoint and a bucket name are not
secrets and typing them blind is how you get a typo you cannot see.

Nothing is ever printed back: the confirmation lists key NAMES and value
lengths, never values.

⚠️ Writing an existing path creates a new KV version rather than merging. Pass
every field the path should hold, not just the ones that changed.
"""
from __future__ import annotations

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
MOUNT = os.environ.get("OPENBAO_MOUNT", "homelab")


def api(path: str, body: dict | None = None, method: str | None = None,
        token: str | None = None) -> dict:
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Content-Type": "application/json"}
    if token:
        headers["X-Vault-Token"] = token
    req = urllib.request.Request(
        f"{ADDR}/v1/{path}", data=data, headers=headers,
        method=method or ("POST" if data else "GET"),
    )
    ctx = ssl.create_default_context(cafile=CA)
    with urllib.request.urlopen(req, context=ctx, timeout=20) as r:
        raw = r.read()
    return json.loads(raw) if raw else {}


def decode(encoded: str, otp: str) -> str:
    """XOR the encoded token with the OTP. Raw base64, so pad it back first."""
    padded = encoded + "=" * (-len(encoded) % 4)
    return bytes(a ^ b for a, b in zip(base64.b64decode(padded), otp.encode())).decode()


def mint_root() -> str:
    if api("sys/generate-root/attempt").get("started"):
        sys.exit("a ceremony is already in progress - run "
                 "./scripts/vault-generate-root.py --cancel first")
    start = api("sys/generate-root/attempt", {})
    nonce, otp, needed = start["nonce"], start["otp"], start["required"]
    print(f"\n{needed} unseal shares expected (input is hidden).", file=sys.stderr)
    try:
        accepted = 0
        while accepted < needed:
            key = getpass.getpass(f"  share {accepted + 1}/{needed}: ")
            if not key.strip():
                sys.exit("empty share, aborting")
            try:
                res = api("sys/generate-root/update",
                          {"key": key.strip(), "nonce": nonce})
            except urllib.error.HTTPError as exc:
                # A mistyped share should cost one retry, not the whole run and
                # the shares already entered. The server rejects it without
                # counting it, so the ceremony is still good.
                detail = exc.read().decode(errors="replace")[:200]
                print(f"    share refused ({exc.code}): {detail}\n"
                      "    enter this share again.", file=sys.stderr)
                continue
            accepted = res.get("progress", accepted + 1)
            if res.get("complete"):
                return decode(res["encoded_token"], otp)
            print(f"    {accepted}/{res['required']} accepted", file=sys.stderr)
        sys.exit("incomplete ceremony")
    except BaseException:
        # Never leave a half-finished attempt: it blocks the next one.
        api("sys/generate-root/attempt", method="DELETE")
        raise


def main() -> int:
    if len(sys.argv) < 3:
        sys.exit(
            "usage: vault-put.py <path under homelab/> <field>[:secret] ...\n"
            "  ./scripts/vault-put.py offsite r2_endpoint r2_bucket \\\n"
            "      r2_access_key_id:secret r2_secret_access_key:secret \\\n"
            "      restic_password:secret"
        )
    path, fields = sys.argv[1], sys.argv[2:]

    payload = {}
    print(f"Secret {MOUNT}/{path} - {len(fields)} field(s).", file=sys.stderr)
    for field in fields:
        name, _, kind = field.partition(":")
        value = (getpass.getpass(f"  {name} (hidden): ") if kind == "secret"
                 else input(f"  {name}: "))
        if not value.strip():
            sys.exit(f"field {name} is empty, aborting")
        payload[name] = value.strip()

    token = mint_root()
    try:
        api(f"{MOUNT}/data/{path}", {"data": payload}, token=token)
        written = api(f"{MOUNT}/data/{path}", token=token)["data"]["data"]
        print("\nwritten:", file=sys.stderr)
        for k in sorted(written):
            print(f"  {k:<24} {len(written[k])} characters", file=sys.stderr)
    finally:
        # In a finally on purpose: the token has no expiry, so a crash between
        # the write and here would leave a permanent root credential behind.
        try:
            api("auth/token/revoke-self", {}, token=token)
            print("temporary root token revoked", file=sys.stderr)
        except urllib.error.HTTPError as exc:
            print(f"⚠️  REVOCATION FAILED ({exc.code}) - revoke it by hand",
                  file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
