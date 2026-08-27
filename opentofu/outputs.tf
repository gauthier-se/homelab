output "containers" {
  description = "Map of provisioned containers → their VMID, hostname and IPv4 address (feeds the Ansible inventory)"
  value = {
    for name, mod in module.containers : name => {
      vm_id = mod.vm_id
      host  = mod.hostname
      ip    = mod.ipv4_address
    }
  }
}

output "vms" {
  description = "Map of provisioned VMs → their VMID, name and IPv4 address. Not part of the Ansible inventory: these guests are configured by their own Nix flake."
  value = {
    for name, mod in module.vms : name => {
      vm_id = mod.vm_id
      host  = mod.hostname
      ip    = mod.ipv4_address
    }
  }
}

# No `ip` key, unlike the two above: HAOS does not read cloud-init, so this
# configuration never tells it an address, the address is set in the guest and
# reported by Proxmox through the agent. Publishing one here would be a claim
# OpenTofu cannot back. Like the dev box, these guests are not in the Ansible
# inventory.
output "haos_vms" {
  description = "Map of provisioned Home Assistant OS VMs → their VMID and name"
  value = {
    for name, mod in module.haos_vms : name => {
      vm_id = mod.vm_id
      host  = mod.hostname
    }
  }
}
