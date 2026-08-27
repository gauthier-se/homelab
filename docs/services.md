# What runs

The state of the lab as it stands. The authority is
[`opentofu/locals.tf`](../opentofu/locals.tf) for the guests and
[`ansible/roles/traefik/defaults/main.yml`](../ansible/roles/traefik/defaults/main.yml)
for the routes; this page is those two, read together.

Everything below runs on one Proxmox node. Every guest is an LXC configured by
Ansible except the two noted at the bottom.

## Guests

### Management (VLAN 10)

| ID | Guest | Address | Runs | CPU / RAM |
|----|-------|---------|------|-----------|
| 120 | `unifi` | `10.10.10.10` | UniFi Network controller | 2 / 2 GB |

### Core (VLAN 25)

| ID | Guest | Address | Runs | CPU / RAM |
|----|-------|---------|------|-----------|
| 250 | `openbao` | `10.10.25.10` | OpenBao: secrets and the private PKI | 2 / 1 GB |
| 251 | `authentik` | `10.10.25.11` | Authentik: SSO and identity provider | 2 / 2 GB |

Core is the locked-down segment. Nothing else reaches it except on the two
service ports applications actually need, and it never initiates outward.

### Servers (VLAN 20)

| ID | Guest | Address | Runs | CPU / RAM |
|----|-------|---------|------|-----------|
| 200 | `traefik` | `10.10.20.2` | Internal reverse proxy, Let's Encrypt wildcard | 1 / 512 MB |
| 210 | `jellyfin` | `10.10.20.10` | Jellyfin, iGPU passthrough for transcoding | 4 / 4 GB |
| 211 | `arr` | `10.10.20.11` | Radarr, Sonarr, Lidarr, Bazarr, Prowlarr, Seerr, Audiobookshelf | 4 / 4 GB |
| 212 | `qbittorrent` | `10.10.20.12` | qBittorrent behind a gluetun VPN kill-switch | 2 / 2 GB |
| 213 | `samba` | `10.10.20.13` | SMB shares onto the 18 TB disk | 2 / 512 MB |
| 214 | `dashboard` | `10.10.20.14` | Homepage and Uptime Kuma | 2 / 2 GB |
| 215 | `freshrss` | `10.10.20.15` | FreshRSS and PostgreSQL | 2 / 1.5 GB |
| 216 | `obsidian-sync` | `10.10.20.16` | CouchDB, obsidian-livesync backend | 2 / 1 GB |
| 218 | `linkding` | `10.10.20.18` | Linkding, SQLite | 2 / 1 GB |
| 220 | `devbox` | `10.10.20.20` | NixOS dev box (VM) | 4 / 8 GB |

217 is reserved and deliberately skipped: renumbering a guest later costs more
than leaving a gap.

### IoT (VLAN 40)

| ID | Guest | Runs | CPU / RAM |
|----|-------|------|-----------|
| 230 | `homeassistant` | Home Assistant OS (VM), Matter controller | 2 / 4 GB |

### DMZ (VLAN 60)

| ID | Guest | Address | Runs | CPU / RAM |
|----|-------|---------|------|-----------|
| 260 | `dmz-traefik` | `10.10.60.2` | Public entry point | 1 / 512 MB |

The DMZ runs the same Traefik role as the internal one, with different inputs:
no wildcard, no SSO, and a route list of its own. CrowdSec runs in front of it.

## Routes

Every name resolves to the internal Traefik and exists only inside the network,
under one wildcard certificate. Adding a service is a routing change, not a new
certificate order.

| Route | Backend | Auth |
|-------|---------|------|
| `jellyfin` | Jellyfin | open |
| `requests` | Seerr | open |
| `books` | Audiobookshelf | open |
| `rss` | FreshRSS | its own OIDC against Authentik |
| `links` | Linkding | its own OIDC against Authentik |
| `obsidian` | CouchDB | none: an API with no interactive login |
| `radarr` `sonarr` `lidarr` `bazarr` `prowlarr` | \*arr stack | forward-auth |
| `torrents` | qBittorrent | forward-auth |
| `dash` `status` | Homepage, Uptime Kuma | forward-auth |
| `bao` | OpenBao UI | forward-auth |
| `auth` | Authentik | it is the identity provider |
| `ha` | Home Assistant | open, X-Forwarded-For stripped |

Three categories of "open" here, and they are not the same thing:

- **Jellyfin, Seerr and Audiobookshelf** cannot sit behind forward-auth: TV and
  phone apps cannot follow an SSO redirect.
- **FreshRSS and Linkding** authenticate against Authentik themselves, over
  OIDC. Putting forward-auth in front of them as well would break the mobile
  clients that use their APIs, which never see the web login.
- **CouchDB** has no interactive login at all. Its one client is a plugin
  holding a token.

No `unifi` route, on purpose: the controller is on Management, and the matrix
denies Servers to Management. Reach it directly or over the tailnet.

## The two self-configuring guests

`devbox` and `homeassistant` are VMs, not LXCs, and neither is in the Ansible
inventory. Neither has apt or general-purpose SSH; both install and configure
themselves. The reasoning is in [architecture.md](architecture.md).

## Not built yet

A second Proxmox node, a Kubernetes cluster on it, a NAS, observability
(Prometheus, Grafana, Loki) and a SIEM. The addressing plan and the firewall
matrix already have room for all of it.
