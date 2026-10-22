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
