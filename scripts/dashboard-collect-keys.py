#!/usr/bin/env python3
"""Fill the `homelab/dashboard` secret with the credentials nobody can derive.

Homepage needs one read credential per service it summarises. The *arr half of
that list is no longer here: those applications generate their own API keys and
keep them in their own config files, so the `dashboard` role reads them at play
time from the host that holds them (see `dashboard_arr_discover` in the role's
defaults). A value Ansible can read on a host it manages does not belong in the
vault as well.

What is left is the half with no file to read: keys minted in a web interface,
and account credentials. Those need a human, which is what this is.

    export OPENBAO_ADDR=https://10.10.25.10:8200
    export OPENBAO_TOKEN=...          # needs write on homelab/dashboard
    export OPENBAO_CACERT=/path/to/homelab-root-ca.pem
    python3 scripts/dashboard-collect-keys.py

Every prompt is skippable: a key that is not supplied simply means that widget
is not rendered, and the role re-runs happily later. Nothing is ever printed
back, and nothing is written to disk here. Re-running is safe: existing keys are
merged, not replaced, so the secret can be filled in over several passes.
"""
from __future__ import annotations

import argparse
import getpass
import os
import sys

MOUNT = "homelab"
PATH = "dashboard"

# Asked for, because there is no file to read them from. The second element is
# what to tell the person about where to find it.
PROMPTS = [
    ("proxmox_token_id", "Proxmox API token, full ID (e.g. homepage@pve!dashboard)"),
    ("proxmox_token_secret", "Proxmox API token secret"),
    ("unifi_username", "UniFi local read-only account, username"),
    ("unifi_password", "UniFi local read-only account, password"),
    ("opnsense_key", "OPNsense API key (System > Access > Users > API keys)"),
    ("opnsense_secret", "OPNsense API secret"),
    ("jellyfin_key", "Jellyfin API key (Dashboard > API keys)"),
    ("audiobookshelf_token", "Audiobookshelf API token (Config > Users > your account)"),
    ("authentik_token", "Authentik API token (Directory > Tokens, intent: API token)"),
    ("qbittorrent_username", "qBittorrent WebUI username"),
    ("qbittorrent_password", "qBittorrent WebUI password"),
]

SECRET_PROMPTS = {
    "proxmox_token_secret",
    "unifi_password",
    "opnsense_secret",
    "jellyfin_key",
    "audiobookshelf_token",
    "authentik_token",
    "qbittorrent_password",
}


def prompt_missing(existing: dict[str, str]) -> dict[str, str]:
    """Ask for the credentials that have no file to read, skipping known ones."""
    collected: dict[str, str] = {}
    print("\nPress Enter to skip any of these, the widget is simply not rendered.\n")
    for name, hint in PROMPTS:
        if name in existing:
            print(f"  · {name}: already set, leaving alone")
            continue
        reader = getpass.getpass if name in SECRET_PROMPTS else input
        try:
            value = reader(f"  {hint}: ").strip()
        except EOFError:
            # No terminal, running from a pipe, CI, or an agent. Treat it as
            # "skip everything remaining" rather than dying.
            print("\n  (no input available, skipping the remaining prompts)")
            break
        if value:
            collected[name] = value
    return collected


def main() -> int:
    argparse.ArgumentParser(description=__doc__.splitlines()[0]).parse_args()

    try:
        import hvac
    except ImportError:
        print("hvac is missing, run this from `nix develop`.", file=sys.stderr)
        return 1

    addr = os.environ.get("OPENBAO_ADDR")
    token = os.environ.get("OPENBAO_TOKEN")
    if not addr or not token:
        print("Set OPENBAO_ADDR and OPENBAO_TOKEN first.", file=sys.stderr)
        return 1

    # Verifying the vault is the whole reason the private CA exists; skipping it
    # here would undo that for the one operation that carries every credential.
    ca_cert = os.environ.get("OPENBAO_CACERT")
    if not ca_cert:
        print("Set OPENBAO_CACERT to the root CA, refusing to skip verification.", file=sys.stderr)
        return 1

    client = hvac.Client(url=addr, token=token, verify=ca_cert)

    # Merge rather than replace, so a second pass can fill in what the first
    # one skipped without wiping what it found.
    try:
        current = client.secrets.kv.v2.read_secret_version(
            path=PATH, mount_point=MOUNT, raise_on_deleted_version=True
        )["data"]["data"]
    except Exception:
        current = {}
    if current:
        print(f"Existing secret has {len(current)} key(s).")

    merged = {**current, **prompt_missing(current)}

    if merged == current:
        print("\nNothing changed.")
        return 0

    client.secrets.kv.v2.create_or_update_secret(
        path=PATH, secret=merged, mount_point=MOUNT
    )
    print(f"\nWrote {len(merged)} key(s) to {MOUNT}/{PATH}.")
    print("Now replay the role:  ansible-playbook site.yml --tags dashboard")
    return 0


if __name__ == "__main__":
    sys.exit(main())
