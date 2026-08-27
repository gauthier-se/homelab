variable "vm_id" {
  description = "Virtual machine VMID"
  type        = number
}

variable "hostname" {
  description = "VM name in Proxmox (HAOS sets its own hostname internally)"
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
  description = "RAM in MiB. Unlike an LXC cap this is a real reservation, the node hands the whole amount to KVM."
  type        = number
  default     = 4096
}

variable "disk_size" {
  description = "Root disk size in GiB. The HAOS image is ~6 GiB and grows to this on import; it holds the config, the add-on containers and the recorder database."
  type        = number
  default     = 32
}

variable "datastore_id" {
  description = "Datastore for the VM disks (root, EFI vars)"
  type        = string
}

variable "image_file_id" {
  description = <<-EOT
    Volume ID of the HAOS disk image. Unlike the NixOS seed, this image *is* the
    installed system: nothing rewrites it afterwards, and an in-place HAOS
    update replaces its content without touching this resource.

    It cannot be fetched by `proxmox_virtual_environment_download_file`: HAOS
    only publishes `.qcow2.xz`, and the provider's decompression only covers
    gz/lzo/zst/bz2. It is staged on the node by scripts/haos-image.sh.
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

variable "keyboard_layout" {
  description = "Keyboard layout of the Proxmox console (noVNC/SPICE), not of the guest"
  type        = string
  default     = "fr"
}
