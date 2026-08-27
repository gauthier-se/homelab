output "vm_id" {
  description = "The VM's VMID"
  value       = proxmox_virtual_environment_vm.this.vm_id
}

output "hostname" {
  description = "The VM name"
  value       = var.hostname
}

output "ipv4_address" {
  description = "The VM's IPv4 address (without the CIDR suffix)"
  value       = split("/", var.ipv4_address)[0]
}
