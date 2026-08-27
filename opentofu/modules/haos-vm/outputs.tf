output "vm_id" {
  description = "The VM's VMID"
  value       = proxmox_virtual_environment_vm.this.vm_id
}

output "hostname" {
  description = "The VM name"
  value       = var.hostname
}
