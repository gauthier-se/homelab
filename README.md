# Homelab

Network design and infrastructure-as-code for a home lab: OpenTofu provisions
the guests, Ansible configures them, OpenBao holds the secrets, Authentik sits
in front of the admin apps, and a segmented network runs underneath.

It was first built by hand, then rebuilt from this code after a full wipe. A
complete replay reports zero changes today.

![The lab: OPNsense router, 2.5 GbE switch, Proxmox node, 18 TB disk and the UniFi access point](docs/images/lab.jpg)

## What it is

- **Segmented network.** Seven VLANs by role and trust level, deny by default,
  the admin plane isolated from the data plane.
- **Everything in code.** No guest is configured by hand. The one machine whose
  install is manual is the hypervisor itself, and even its operational tooling
  is a role.
- **Real TLS everywhere.** A Let's Encrypt wildcard over DNS-01 with
  split-horizon DNS internally, a private PKI for the infrastructure, remote
  access over Tailscale only.
- **Nothing is published by default.** Anything that needs an inbound path goes
  in the DMZ, behind a second reverse proxy with rules of its own. Everything
  else stops at the network edge.

## Hardware

| Role | Device | Specification |
|------|--------|---------------|
| Router / firewall | Intel N100 mini PC | 8 GB RAM, 250 GB SSD, 4x2.5 GbE (i226-V), OPNsense |
| Hypervisor (node 1) | Nipogi CK10 | i5-12600H, 32 GB, 1 TB NVMe, Proxmox VE |
| Media storage | 18 TB HDD | USB, attached to node 1 |
| Switch | Mokerlink 2.5 GbE | 8x2.5 GbE + 1xSFP+ 10G, managed, 802.1Q |
| Access point | UniFi U7 Pro | WiFi 7, multi-SSID to VLAN, 2.5 G PoE+ injector |
| Hypervisor (node 2) | Minisforum MS-01 *(planned)* | i5-12600H, 64 GB, 2x1 TB NVMe, SFP+ 10 GbE |
| NAS *(planned)* | Jonsbo N3 + N305 board | 8 bays, 4x8 TB ZFS RAIDZ2, 2.5 GbE |

## Stack

### Platform

| | Tool | Role |
|---|------|------|
| <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/proxmox.png" width="18" align="top"> | **Proxmox VE** | Virtualisation. Two independent nodes rather than a cluster |
| <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/opnsense.png" width="18" align="top"> | **OPNsense** | Routing, inter-VLAN firewall, Unbound DNS, Kea DHCP |
| <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/tailscale.png" width="18" align="top"> | **Tailscale** | Remote access: subnet router and exit node |
| <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/opentofu.png" width="18" align="top"> | **OpenTofu** | VM and LXC provisioning, `bpg/proxmox` provider |
| <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/ansible.png" width="18" align="top"> | **Ansible** | Host and service configuration |
| <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/nixos.png" width="18" align="top"> | **Nix** | One devshell, same tool versions everywhere |

### Identity, secrets, edge

| | Tool | Role |
|---|------|------|
| <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/openbao.png" width="18" align="top"> | **OpenBao** | Secrets and the private PKI |
| <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/authentik.png" width="18" align="top"> | **Authentik** | SSO and identity provider, Traefik forward-auth |
| <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/traefik.png" width="18" align="top"> | **Traefik** | Reverse proxy, Let's Encrypt wildcard over DNS-01 |
| <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/crowdsec.png" width="18" align="top"> | **CrowdSec** | Log-driven banning in front of the public entry point |

### Applications

| | Tool | Role |
|---|------|------|
| <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/jellyfin.png" width="18" align="top"> | **Jellyfin** | Media server, iGPU passthrough |
| <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/seerr.png" width="18" align="top"> | **Seerr** | Request front end |
| <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/radarr.png" width="18" align="top"> <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/sonarr.png" width="18" align="top"> <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/lidarr.png" width="18" align="top"> <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/bazarr.png" width="18" align="top"> <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/prowlarr.png" width="18" align="top"> | **\*arr stack** | Radarr, Sonarr, Lidarr, Bazarr, Prowlarr |
| <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/qbittorrent.png" width="18" align="top"> | **qBittorrent** | Behind a gluetun VPN kill-switch |
| <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/audiobookshelf.png" width="18" align="top"> | **Audiobookshelf** | Audiobooks and podcasts |
| <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/samba-server.png" width="18" align="top"> | **Samba** | SMB shares onto the 18 TB disk |
| <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/homepage.png" width="18" align="top"> | **Homepage** | Landing page, generated from the proxy's route list |
| <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/uptime-kuma.png" width="18" align="top"> | **Uptime Kuma** | Availability history |
| <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/freshrss.png" width="18" align="top"> | **FreshRSS** | RSS reader, OIDC against Authentik |
| <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/linkding.png" width="18" align="top"> | **Linkding** | Bookmarks, OIDC against Authentik |
| <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/couchdb.png" width="18" align="top"> | **CouchDB** | obsidian-livesync backend |
| <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/home-assistant.png" width="18" align="top"> | **Home Assistant** | Home automation, Matter over Thread |
| <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/unifi.png" width="18" align="top"> | **UniFi** | Network controller |

### Planned

| | Tool | Role |
|---|------|------|
| <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/kubernetes.png" width="18" align="top"> | **k3s / Talos** | Kubernetes on node 2 |
| <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/prometheus.png" width="18" align="top"> <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/grafana.png" width="18" align="top"> <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/loki.png" width="18" align="top"> | **Observability** | Prometheus, Grafana, Loki |

## Network

```mermaid
flowchart TD
    NET([Internet]) --> FB[ISP box<br/>bridge mode]
    FB --> WAN[OPNsense WAN<br/>public IP]
    WAN --> OPN[OPNsense<br/>router / firewall]
    OPN <-->|802.1Q trunk| SW[Switch<br/>2.5 GbE]
    SW --- PVE1[Proxmox 01<br/>+ 18 TB media]
    SW --- PVE2[Proxmox 02<br/>planned]
    SW --- AP[Access point<br/>SSID to VLAN]

    subgraph VLANs
      V10[10 Management]
      V25[25 Core/Infra]
      V20[20 Servers]
      V30[30 Trusted]
      V40[40 IoT]
      V50[50 Guest]
      V60[60 DMZ]
    end
    OPN -.-> VLANs
    OPN --> TS[[Tailscale<br/>exit node + routes]]
```

`10.10.<vlan>.0/24`, gateway `.1`, static `.2-.99`, DHCP `.100-.199`.

## Documentation

| | |
|---|---|
| [docs/architecture.md](docs/architecture.md) | VLAN plan, firewall matrix, TLS design |
| [docs/services.md](docs/services.md) | Every guest and every route, as they stand |
| [docs/bootstrap.md](docs/bootstrap.md) | From a bare hypervisor to a lab that answers |

## Layout

```
opentofu/   VM and LXC provisioning: a guest catalogue plus three modules
ansible/    configuration: one role per service, one playbook
scripts/    the few things neither tool can do
docs/       architecture, inventory, bootstrap
```

## Getting started

Everything runs from one devshell:

```sh
nix develop                # tofu, ansible, ansible-lint, yamllint, hvac
```

Then fill in the three untracked files that carry the real identifiers, each of
which has a committed `.example` next to it:

```sh
cp opentofu/secrets.auto.tfvars.example        opentofu/secrets.auto.tfvars
cp ansible/inventory/hosts.yml.example         ansible/inventory/hosts.yml
cp ansible/group_vars/all/99-local.yml.example ansible/group_vars/all/99-local.yml
```

Provision, then configure:

```sh
(cd opentofu && tofu init && tofu apply)
(cd ansible && ansible-playbook site.yml)
```

The full path from a bare hypervisor is in [docs/bootstrap.md](docs/bootstrap.md).

The same gates that run in CI run locally:

```sh
(cd opentofu && tofu fmt -check -recursive && tofu init -backend=false && tofu validate)
(cd ansible && ansible-lint) && yamllint --strict .
```

## Secrets

**No secret is committed, not even encrypted.** OpenBao is the single source of
truth, and the bootstrap material that opens it lives outside any working tree,
under `$HOMELAB_SECRETS` (`~/.config/homelab` by default).

There is no permanent root token: one is minted from the unseal keys when a new
secret path has to be created, and revoked in the same breath.

The OpenTofu state holds every input in plaintext, so the backend is local and
untracked. gitleaks runs as a pre-commit hook and again in CI.

## License

MIT. See [LICENSE](LICENSE).
