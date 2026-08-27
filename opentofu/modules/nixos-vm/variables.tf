variable "vm_id" {
  description = "Virtual machine VMID"
  type        = number
}

variable "hostname" {
  description = "VM name in Proxmox (the guest sets its own hostname, see the NixOS config)"
  type        = string
}

variable "description" {
  description = "Free-text description shown in the Proxmox UI"
  type        = string
  default     = "Managed by OpenTofu"
}

variable "node_name" {
  description = "Proxmox node hosting the VM"
  type        = string
}

variable "tags" {
  description = "Proxmox tags (used for grouping in the UI)"
  type        = list(string)
  default     = []
}

variable "cores" {
  description = "vCPU cores"
  type        = number
  default     = 2
}

variable "memory" {
  description = "RAM in MiB"
  type        = number
  default     = 2048
}

variable "disk_size" {
  description = "Root disk size in GiB (the seed image is resized to it on import)"
  type        = number
  default     = 32
}

variable "datastore_id" {
  description = "Datastore for the VM disks (root, EFI vars, cloud-init drive)"
  type        = string
}

variable "seed_image_file_id" {
  description = <<-EOT
    Volume ID of the cloud image the disk is created from. It is a seed, not the
    installed system: nixos-anywhere kexecs into the NixOS installer and rewrites
    the whole disk with disko. The image only has to boot far enough to accept
    an SSH connection as root.
  EOT
  type        = string
}

variable "start_order" {
  description = "Boot order (lower starts first)"
  type        = number
  default     = 3
}

variable "bridge" {
  description = "Network bridge"
  type        = string
}

variable "vlan_id" {
  description = "VLAN tag for the VM's NIC"
  type        = number
}

variable "ipv4_address" {
  description = "Static IPv4 address in CIDR notation, handed to the seed image through cloud-init. The installed system declares the same address itself (NixOS does not read cloud-init)."
  type        = string
}

variable "ipv4_gateway" {
  description = "IPv4 gateway"
  type        = string
}

variable "nameservers" {
  description = "DNS servers"
  type        = list(string)
  default     = ["10.10.20.1"]
}

variable "public_key" {
  description = "SSH public key authorized for root on the seed image, the key that runs nixos-anywhere. The installed system authorizes its own keys, declared in the NixOS config."
  type        = string
}

variable "keyboard_layout" {
  description = "Keyboard layout of the Proxmox console (noVNC/SPICE), not of the guest"
  type        = string
  default     = "fr"
}
