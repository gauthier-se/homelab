terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}

# A VM seeded from a cloud image and then overwritten by nixos-anywhere.
# Nothing below describes the installed system, that lives in the dotfiles
# flake (`#devbox`). A VM and not an LXC because nixos-anywhere installs by
# repartitioning a real disk, which an LXC does not have. Like the HAOS VM it
# is deliberately absent from the Ansible inventory: it configures itself.
resource "proxmox_virtual_environment_vm" "this" {
  node_name       = var.node_name
  vm_id           = var.vm_id
  name            = var.hostname
  description     = var.description
  tags            = var.tags
  keyboard_layout = var.keyboard_layout

  on_boot = true
  startup {
    order = var.start_order
  }

  # The guest runs qemu-guest-agent, so Proxmox can report the IP and ask for a
  # clean shutdown. `stop_on_destroy` is the fallback mid-install, when no agent
  # is listening yet.
  agent {
    enabled = true
    timeout = "5m"
  }
  stop_on_destroy = true

  cpu {
    cores = var.cores
    # No cluster and no live migration, so there is no CPU compatibility to
    # preserve, and nested KVM plus AES only exist under `host`.
    type = "host"
  }

  memory {
    dedicated = var.memory
  }

  # systemd-boot. Secure Boot stays off: a NixOS kernel is unsigned, and
  # enrolling keys would leave the VM unbootable after the install.
  bios    = "ovmf"
  machine = "q35"
  efi_disk {
    datastore_id      = var.datastore_id
    type              = "4m"
    pre_enrolled_keys = false
  }

  disk {
    datastore_id = var.datastore_id
    file_id      = var.seed_image_file_id
    interface    = "virtio0"
    size         = var.disk_size
    discard      = "on"
  }

  network_device {
    bridge  = var.bridge
    vlan_id = var.vlan_id
  }

  # cloud-init, consumed by the seed image only, NixOS ignores this drive and
  # declares the same address itself. The catalogue entry feeds both.
  initialization {
    datastore_id = var.datastore_id

    ip_config {
      ipv4 {
        address = var.ipv4_address
        gateway = var.ipv4_gateway
      }
    }

    dns {
      servers = var.nameservers
    }

    user_account {
      username = "root"
      keys     = [trimspace(var.public_key)]
    }
  }

  operating_system {
    type = "l26"
  }

  # Cloud images log their boot to ttyS0; without a serial device the console
  # shows nothing at all when the seed fails to come up.
  serial_device {}

  lifecycle {
    # The seed is meaningless once nixos-anywhere has rewritten the disk.
    # Without this, a refreshed upstream image would plan a *replacement* of a
    # live machine.
    ignore_changes = [disk[0].file_id]
  }
}
