# Bootstrap

From a bare hypervisor to a lab that answers. The ordering matters: several
layers read secrets that a layer below has to be serving first.

## 0. Prerequisites

- **OPNsense installed**, VLANs and the inter-VLAN matrix configured, DHCP and
  Unbound serving. This layer is not in this repository yet; the design it
  implements is in [architecture.md](architecture.md).
- **Proxmox VE installed** on the node. This is the one machine whose install is
  manual. Its operational tooling is not: that is the `proxmox_host` role.
- **A wildcard-capable DNS provider** for the DNS-01 challenge (Cloudflare
  here), and an API token for it.
- **Nix**, for the devshell.

```sh
nix develop
```

The shell brings OpenTofu, Ansible, the linters and `hvac`, exports
`$HOMELAB_SECRETS`, and warns when the OpenBao tokens are running short.

## 1. Local identifiers

Three files carry the real values and none of them is committed. Each has an
`.example` beside it that documents every field:

```sh
cp opentofu/secrets.auto.tfvars.example        opentofu/secrets.auto.tfvars
cp ansible/inventory/hosts.yml.example         ansible/inventory/hosts.yml
cp ansible/group_vars/all/99-local.yml.example ansible/group_vars/all/99-local.yml
```

Note that OpenTofu authenticates to Proxmox with a **username and password**,
not an API token. Proxmox reserves the LXC feature flags (`keyctl`) and device
passthrough to the real `root@pam` account and answers 403 to a token, including
root's own.

## 2. Provision the guests

```sh
cd opentofu
tofu init
tofu apply
```

The guest catalogue is [`locals.tf`](../opentofu/locals.tf): one entry per LXC
carrying its VLAN, address, resources, and any Docker, passthrough or mount it
needs. `main.tf` is a `for_each` over that catalogue into three modules.

The state is local and untracked, and it holds every input in plaintext. Back it
up somewhere that is not this directory.

If the Home Assistant VM is in scope, stage its image first: OpenTofu cannot,
because HAOS publishes only an `.xz` and the provider does not decompress that
format.

```sh
./scripts/haos-image.sh
```

## 3. Baseline every container

```sh
cd ansible
ansible-galaxy collection install -r requirements.yml -p collections
ansible-playbook site.yml --tags base
```

This runs before the vault exists, which is the point: the roles above it
consume secrets that something has to be serving first.

## 4. Bring up the vault, then seed it

```sh
ansible-playbook site.yml --tags secrets
```

Then initialise OpenBao, keep the unseal keys somewhere that is not this machine
alone, enable the KV mount and the PKI, and export the root CA to
`$HOMELAB_SECRETS/homelab-root-ca.pem`, which is what every later lookup
verifies against.

Write the secrets each role expects. The `defaults/` files mark them with a
`CHANGE_ME_VIA_OPENBAO` placeholder, so grepping for it lists exactly what is
missing:

```sh
rg CHANGE_ME_VIA_OPENBAO ansible/roles
./scripts/vault-put.py traefik cf_token:secret
```

`vault-put.py` runs the whole root ceremony around the write and revokes the
token in a `finally`. There is no permanent root token to find, by design.

Two tokens are then minted for day-to-day use, both periodic, which means
renewable forever and dead the moment nobody renews them:

```sh
./scripts/vault-renew-tokens.sh --check
```

Run that weekly from a timer. Both had quietly run down to seven days once.

## 5. The rest, in dependency order

```sh
ansible-playbook site.yml
```

Or one layer at a time, which is the same order `site.yml` uses:

| Tag | Brings up |
|-----|-----------|
| `node` | Proxmox host tooling: backups to object storage, disk alerts, verification timers |
| `base` | Baseline on every container |
| `secrets` | OpenBao and the private PKI |
| `sso` | Authentik |
| `proxy` | CrowdSec and the internal Traefik |
| `dmz` | The public entry point: the same role, different inputs |
| `media` | Jellyfin, the \*arr stack, the download client behind its VPN |
| `shares` | Samba |
| `personal` | FreshRSS, the Obsidian sync backend, Linkding |
| `dashboard` | Homepage and Uptime Kuma |
| `unifi` | The UniFi controller |

`dashboard` is last on purpose: its widgets read the services every play above
installs, and its reachability dots only mean something once those are running.

## 6. Fill in the dashboard widgets

The six \*arr API keys need nothing: the role reads them at play time from the
host that generated them. The rest have no file to read, because they are minted
in a web interface or they are account credentials:

```sh
export OPENBAO_ADDR=https://10.10.25.10:8200
export OPENBAO_TOKEN=...          # needs write on homelab/dashboard
export OPENBAO_CACERT=$HOMELAB_SECRETS/homelab-root-ca.pem
python3 scripts/dashboard-collect-keys.py
ansible-playbook site.yml --tags dashboard
```

Every prompt is skippable. A missing key is not an error: that widget is simply
not rendered, and the play stays green. A dashboard that fails to deploy because
the vault is sealed would be missing at exactly the moment you want to look at
one.

## Verifying

A replay reports zero changes when the lab matches the code:

```sh
ansible-playbook site.yml --diff
```

The same gates CI runs:

```sh
(cd opentofu && tofu fmt -check -recursive && tofu init -backend=false && tofu validate)
(cd ansible && ansible-lint) && yamllint --strict .
```
