# Architecture

## Addressing

`10.10.<vlan>.0/24` throughout. Gateway on `.1` (OPNsense), static `.2-.99`,
DHCP `.100-.199`, reserved `.200-.254`.

| VLAN | Name | Subnet | Holds |
|------|------|--------|-------|
| 10 | Management | `10.10.10.0/24` | **Admin plane**: OPNsense, Proxmox nodes, switch, access point, IPMI |
| 20 | Servers/Apps | `10.10.20.0/24` | Media, monitoring, internal Traefik, general applications |
| 25 | Core/Infra | `10.10.25.0/24` | **Crown jewels**: OpenBao, Authentik |
| 30 | Trusted | `10.10.30.0/24` | Laptops, desktops and phones that belong here |
| 40 | IoT | `10.10.40.0/24` | Connected devices, TV, home automation |
| 50 | Guest | `10.10.50.0/24` | Visitors, internet only |
| 60 | DMZ | `10.10.60.0/24` | Internet-exposed services, behind their own Traefik |

The guest catalogue in [`opentofu/locals.tf`](../opentofu/locals.tf) is the
authority on which address belongs to what.

**Segmentation is by role and trust level, never by physical machine.** A VLAN
is a security zone; the firewall filters by function, not by chassis. One VLAN
per node would add no security and would break mobility, since moving a workload
would mean changing both its VLAN and its address.

The admin interfaces of *both* Proxmox nodes live in Management. Their workloads
live in Servers or Core depending on sensitivity.

## Firewall

Deny by default. Every allowance is explicit. Rows are the source, columns the
destination.

| Source \ Dest | Mgmt | Core | Servers | Trusted | IoT | Guest | DMZ | Internet |
|---------------|:----:|:----:|:-------:|:-------:|:---:|:-----:|:---:|:--------:|
| **Management** | yes | yes | yes | yes | yes | yes | yes | yes |
| **Core** | no | yes | no | no | no | no | no | yes |
| **Servers** | cond. | cond. | yes | no | no | no | no | yes |
| **Trusted** | cond. | cond. | yes | yes | yes | no | yes | yes |
| **IoT** | no | no | cond. | no | yes | no | no | cond. |
| **Guest** | no | no | no | no | no | yes | no | yes |
| **DMZ** | no | no | cond. | no | no | no | yes | yes |
| **Internet (inbound)** | no | no | no | no | no | no | 80/443 | - |

Three conditional allowances carry the whole design:

- **Servers to Core** is limited to the service ports applications actually
  need: OpenBao `8200`, Authentik `443/9000`. Core never initiates towards
  another VLAN except for its own updates. An application compromised in Servers
  sees one port of the vault, not the segment.
- **Servers to Management** is one source address, the dashboard guest, towards
  three address:port pairs and nothing else: the Proxmox API, the UniFi
  controller, the OPNsense API. Plus ICMP, for the ping monitors. Every
  credential behind those three is read-only by construction.
- **Internet inbound** reaches the DMZ on 80/443 and stops there. The DMZ runs
  its own Traefik, with the wildcard and the SSO removed.

Rules are written per destination address and port, the way the DMZ rules
already were, never as a host-wide or segment-wide opening. The next service
that wants to read the hypervisor belongs *on the dashboard guest*, not behind a
widened rule.

## TLS

Hybrid, on purpose.

- **A Let's Encrypt wildcard** for the internal domain, issued over DNS-01
  against Cloudflare and terminated by Traefik. Browsers trust it with no CA to
  install on anyone's laptop.
- **Split-horizon DNS**: those names resolve internally, to the internal
  Traefik, and have no public A record.
- **A private OpenBao PKI** for the infrastructure itself: machine certificates
  and HTTPS backends that Traefik verifies rather than trusts blindly.

The public names are deliberately different from the internal ones. A wildcard
lives on the internal instance only; the public entry point asks per name, since
a wildcard on the apex would let a compromised DMZ host mint any name under it.

## The two exceptions

Every guest is an LXC managed by Ansible, except two, and both are exceptions
for the same reason: they configure themselves.

- **The dev box** is a NixOS VM, seeded from a cloud image and then rewritten by
  nixos-anywhere. A VM and not an LXC because that installer repartitions a real
  disk. What it installs lives in a dotfiles flake, not here.
- **Home Assistant OS** is a VM because the supervised install needs its own
  init and container runtime, without which the add-ons do not exist. It sits on
  the IoT VLAN for a physical reason rather than an aesthetic one:
  Matter-over-Thread border routers announce the mesh prefix by ICMPv6 RA on
  their own link only, and those do not cross a router.

Neither is in the Ansible inventory. Neither has apt or general-purpose SSH.
Pointing the `common` role at them would mean nothing.
