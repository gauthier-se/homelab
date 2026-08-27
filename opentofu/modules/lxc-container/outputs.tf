output "vm_id" {
  description = "The container VMID"
  value       = proxmox_virtual_environment_container.this.vm_id
}

output "hostname" {
  description = "The container hostname"
  value       = var.hostname
}

output "ipv4_address" {
  description = "The container's IPv4 address (without the CIDR suffix)"
  value       = split("/", var.ipv4_address)[0]
}
