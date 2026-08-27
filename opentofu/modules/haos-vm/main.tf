terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}

# Home Assistant OS. A VM and not an LXC because HAOS ships its own supervisor,
# init and container runtime, the add-ons (Matter Server, Mosquitto) do not
# exist without it. Like the dev box it is *not* in the Ansible inventory: HAOS
# has no apt and no general-purpose SSH: it configures itself through its UI.
# It sits on the IoT VLAN and not with the other servers, for a physical reason
# rather than an aesthetic one: Matter-over-Thread border routers announce the
# mesh prefix by ICMPv6 RA on their own link only, and those do not cross a
# router. A guest on another VLAN never hears them.
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

  # HAOS ships qemu-guest-agent, so Proxmox can report the IP and ask for a
  # clean shutdown, which matters here: the recorder database is written
  # continuously and a hard stop is how it gets corrupted.
  agent {
    enabled = true
    timeout = "5m"
  }
  stop_on_destroy = true

  cpu {
    cores = var.cores
    type  = "host"
  }

  memory {
    dedicated = var.memory
  }

  # HAOS boots UEFI only: there is no BIOS path in the image. Secure Boot stays
  # off and the keys are left un-enrolled: the image is not signed for it.
  bios    = "ovmf"
  machine = "q35"
  efi_disk {
    datastore_id      = var.datastore_id
    type              = "4m"
    pre_enrolled_keys = false
  }

  disk {
    datastore_id = var.datastore_id
    file_id      = var.image_file_id
    interface    = "virtio0"
    size         = var.disk_size
    discard      = "on"
  }

  # Single NIC on the IoT VLAN, deliberately. Home Assistant has to share a
  # broadcast domain with what it discovers: Thread border routers advertise the
  # mesh prefix by ICMPv6 RA on their own link only, and those do not cross a
  # router, an mDNS reflector fixes discovery, never routing. A second leg on
  # Servers would also bridge two trust zones with no firewall rule permitting
  # it. Traefik reaches this address instead, through one named rule.
  network_device {
    bridge  = var.bridge
    vlan_id = var.vlan_id
  }

  # No `initialization` block: HAOS does not read cloud-init. Its address, DNS
  # and hostname are set once in the HAOS console/UI.

  operating_system {
    type = "l26"
  }

  serial_device {}

  lifecycle {
    # The image is the system. Once HAOS has updated itself in place, the file
    # this was created from no longer describes the disk, and a newer staged
    # image must never plan a *replacement* of a live machine holding the whole
    # home automation state.
    ignore_changes = [disk[0].file_id]
  }
}
