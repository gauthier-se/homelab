# Guest catalogue for node 1. Addressing follows docs/architecture.md.
# The 18 TB media bind-mount keeps its pre-wipe path so Jellyfin watch-state
# and qBittorrent fastresume survive a rebuild.

locals {
  gateways = {
    mgmt    = "10.10.10.1"
    servers = "10.10.20.1"
    core    = "10.10.25.1"
    iot     = "10.10.40.1"
    dmz     = "10.10.60.1"
  }

  containers = {
    # --- Management (VLAN 10) ---
    unifi = {
      vm_id        = 120
      description  = "UniFi Network controller"
      vlan_id      = 10
      ipv4_address = "10.10.10.10/24"
      ipv4_gateway = local.gateways.mgmt
      nameservers  = [local.gateways.mgmt]
      cores        = 2
      memory       = 2048
      disk_size    = 12
      start_order  = 2
      tags         = ["mgmt", "unifi"]
    }

    # --- Core / Infra (VLAN 25) ---
    openbao = {
      vm_id        = 250
      description  = "OpenBao: secrets + private PKI (crown jewel)"
      vlan_id      = 25
      ipv4_address = "10.10.25.10/24"
      ipv4_gateway = local.gateways.core
      nameservers  = [local.gateways.core]
      cores        = 2
      memory       = 1024
      disk_size    = 8
      start_order  = 1
      tags         = ["core", "openbao"]
    }
    authentik = {
      vm_id        = 251
      description  = "Authentik: SSO / IdP (Docker)"
      vlan_id      = 25
      ipv4_address = "10.10.25.11/24"
      ipv4_gateway = local.gateways.core
      nameservers  = [local.gateways.core]
      cores        = 2
      memory       = 2048
      disk_size    = 12
      nesting      = true
      keyctl       = true
      start_order  = 2
      tags         = ["core", "authentik"]
    }

    # --- Servers / Apps (VLAN 20) ---
    traefik = {
      vm_id        = 200
      description  = "Internal Traefik: reverse proxy + Let's Encrypt wildcard"
      vlan_id      = 20
      ipv4_address = "10.10.20.2/24"
      ipv4_gateway = local.gateways.servers
      nameservers  = [local.gateways.servers]
      cores        = 1
      memory       = 512
      disk_size    = 4
      start_order  = 2
      tags         = ["servers", "traefik"]
    }
    jellyfin = {
      vm_id        = 210
      description  = "Jellyfin: media server (iGPU passthrough)"
      vlan_id      = 20
      ipv4_address = "10.10.20.10/24"
      ipv4_gateway = local.gateways.servers
      nameservers  = [local.gateways.servers]
      cores        = 4
      memory       = 4096
      disk_size    = 36
      nesting      = true
      start_order  = 3
      tags         = ["servers", "media", "jellyfin"]
      # gid 44/992 = video/render inside the Debian container, the groups the
      # jellyfin user belongs to. Without them the device lands as root:root and
      # transcoding silently falls back to the CPU.
      #
      # ⚠️ These paths are kernel-enumeration dependent, and the enumeration
      # moved: the 7.0.2-6 kernel exposed the iGPU as card1, 7.0.14-12 exposes it
      # as card0, and the container refused to start on the upgrade with
      # `Device /dev/dri/card1 does not exist`. Re-check after every kernel bump.
      # /dev/dri/by-path/pci-0000:00:02.0-{card,render} is the stable name on the
      # host, but it is not usable here: Proxmox reproduces the literal path
      # inside the container, so the devices land in /dev/dri/by-path/ and
      # Jellyfin, which looks for /dev/dri/renderD128, does not find them.
      device_passthrough = [
        { path = "/dev/dri/card0", gid = 44 },
        { path = "/dev/dri/renderD128", gid = 992 },
      ]
      mount_points = [
        { host_path = "/mnt/hdd/media", container_path = "/mnt/hdd/media" },
      ]
    }
    arr = {
      # 24 GB: a `compose pull` holds the new images alongside the old ones
      # until the prune, so headroom must cover the whole image set (5.5 GB).
      vm_id        = 211
      description  = "*arr stack (Radarr/Sonarr/Lidarr/Bazarr/Prowlarr/Seerr): Docker"
      vlan_id      = 20
      ipv4_address = "10.10.20.11/24"
      ipv4_gateway = local.gateways.servers
      nameservers  = [local.gateways.servers]
      cores        = 4
      memory       = 4096
      disk_size    = 24
      nesting      = true
      keyctl       = true
      start_order  = 3
      tags         = ["servers", "media", "arr"]
      mount_points = [
        { host_path = "/mnt/hdd", container_path = "/mnt/hdd" },
      ]
    }
    qbittorrent = {
      vm_id        = 212
      description  = "qBittorrent behind a VPN (gluetun): Docker"
      vlan_id      = 20
      ipv4_address = "10.10.20.12/24"
      ipv4_gateway = local.gateways.servers
      nameservers  = [local.gateways.servers]
      cores        = 2
      memory       = 2048
      disk_size    = 16
      nesting      = true
      keyctl       = true
      start_order  = 3
      tags         = ["servers", "media", "qbittorrent"]
      device_passthrough = [
        { path = "/dev/net/tun", mode = "0666" },
      ]
      mount_points = [
        { host_path = "/mnt/hdd", container_path = "/mnt/hdd" },
      ]
    }
    samba = {
      vm_id        = 213
      description  = "Samba: media shares over the LAN"
      vlan_id      = 20
      ipv4_address = "10.10.20.13/24"
      ipv4_gateway = local.gateways.servers
      nameservers  = [local.gateways.servers]
      cores        = 2
      memory       = 512
      disk_size    = 8
      start_order  = 3
      tags         = ["servers", "media", "samba"]
      mount_points = [
        { host_path = "/mnt/hdd", container_path = "/mnt/hdd" },
      ]
    }

    # On Servers rather than Management despite reading the admin plane: it is a
    # web app holding credentials, and it needs to sit behind the proxy. Its
    # reads are granted as per-address rules rather than a segment opening:
    # see the firewall matrix in docs/architecture.md.
    dashboard = {
      vm_id        = 214
      description  = "Homepage + Uptime Kuma: landing page and availability monitoring (Docker)"
      vlan_id      = 20
      ipv4_address = "10.10.20.14/24"
      ipv4_gateway = local.gateways.servers
      nameservers  = [local.gateways.servers]
      cores        = 2
      memory       = 2048
      # 16, not 8: the Uptime Kuma image is 2.5 GB and its embedded MariaDB
      # preallocates a 100 MB redo log. At 8 the first start filled the rootfs
      # and the database never initialised.
      disk_size   = 16
      nesting     = true
      keyctl      = true
      start_order = 3
      tags        = ["servers", "dashboard", "monitoring"]
      # Read-only: reporting free space needs no write access.
      mount_points = [
        { host_path = "/mnt/hdd", container_path = "/mnt/hdd", read_only = true },
      ]
    }

    # --- Servers / Apps (VLAN 20), personal services ---
    # Neither depends on the NAS: a few hundred MB each, on local NVMe.
    #
    # 215 / 10.10.20.15 is free: FreshRSS lived there until 21/10/2026.
    obsidian-sync = {
      vm_id        = 216
      description  = "CouchDB, obsidian-livesync backend (Docker)"
      vlan_id      = 20
      ipv4_address = "10.10.20.16/24"
      ipv4_gateway = local.gateways.servers
      nameservers  = [local.gateways.servers]
      cores        = 2
      memory       = 1024
      # CouchDB keeps every revision until a compaction runs, so the database
      # grows with edit history rather than with vault size.
      disk_size   = 12
      nesting     = true
      keyctl      = true
      start_order = 3
      tags        = ["servers", "personal", "obsidian"]
    }

    # 217 / 10.10.20.17 is reserved for a self-hosted application still in
    # development. It joins this catalogue when a release is tagged: building an
    # image is not work a production guest should be doing.

    linkding = {
      # 218, skipping 217: that number is spoken for above, and renumbering a
      # guest later means renumbering its address, its route and its backup job.
      vm_id        = 218
      description  = "Linkding, bookmark manager, SQLite (Docker)"
      vlan_id      = 20
      ipv4_address = "10.10.20.18/24"
      ipv4_gateway = local.gateways.servers
      nameservers  = [local.gateways.servers]
      cores        = 2
      # 1024: uwsgi runs two processes of two threads plus a background task
      # worker, and the database is SQLite rather than a second PostgreSQL. The
      # measured resting set is a few hundred MB, so this is headroom, not need.
      memory = 1024
      # 8 is enough: one image of ~400 MB and no database server beside it.
      # What grows is data/, which holds favicons and
      # link previews: small files, but one per bookmark.
      disk_size   = 8
      nesting     = true
      keyctl      = true
      start_order = 3
      tags        = ["servers", "personal", "linkding"]
    }

    # --- DMZ (VLAN 60), the only guest reachable from the internet ---
    # The smallest thing that can terminate TLS and forward a port. No data, no
    # credentials beyond its ACME account.
    dmz-traefik = {
      vm_id        = 260
      description  = "DMZ Traefik: public entry point"
      vlan_id      = 60
      ipv4_address = "10.10.60.2/24"
      ipv4_gateway = local.gateways.dmz
      nameservers  = [local.gateways.dmz]
      cores        = 1
      memory       = 512
      disk_size    = 4
      start_order  = 2
      tags         = ["dmz", "traefik"]
    }
  }

  # Full VMs. Everything else is an LXC; the dev box is the exception because
  # NixOS owns its own init and filesystem layout, which a container will not
  # hand over.
  vms = {
    devbox = {
      vm_id        = 220
      description  = "NixOS dev box: SSH workspace (nvim/tmux/git/claude). Config: dotfiles flake #devbox, not Ansible"
      vlan_id      = 20
      ipv4_address = "10.10.20.20/24"
      ipv4_gateway = local.gateways.servers
      nameservers  = [local.gateways.servers]
      cores        = 4
      memory       = 8192
      # Nix keeps every previous generation, and `--build-on remote` builds the
      # closure here rather than on a Mac that cannot produce x86_64 binaries.
      disk_size   = 64
      start_order = 3
      tags        = ["servers", "dev", "nixos"]
    }
  }
}
