terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}

resource "proxmox_virtual_environment_container" "this" {
  node_name     = var.node_name
  vm_id         = var.vm_id
  description   = var.description
  tags          = var.tags
  unprivileged  = var.unprivileged
  start_on_boot = true

  startup {
    order = var.start_order
  }

  cpu {
    cores = var.cores
  }

  memory {
    dedicated = var.memory
    swap      = var.swap
  }

  disk {
    datastore_id = var.datastore_id
    size         = var.disk_size
  }

  dynamic "mount_point" {
    for_each = var.mount_points
    content {
      volume    = mount_point.value.host_path
      path      = mount_point.value.container_path
      read_only = mount_point.value.read_only
      backup    = false
    }
  }

  dynamic "device_passthrough" {
    for_each = var.device_passthrough
    content {
      path = device_passthrough.value.path
      gid  = device_passthrough.value.gid
      mode = device_passthrough.value.mode
    }
  }

  network_interface {
    name    = "eth0"
    bridge  = var.bridge
    vlan_id = var.vlan_id
  }

  initialization {
    hostname = var.hostname

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
      keys = [trimspace(var.public_key)]
    }
  }

  operating_system {
    template_file_id = var.template_file_id
    type             = "debian"
  }

  features {
    nesting = var.nesting
    keyctl  = var.keyctl
  }
}
