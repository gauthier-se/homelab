variable "proxmox_endpoint" {
  description = "Proxmox VE API endpoint (e.g. https://10.10.10.3:8006/)"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox VE API token (id=secret). Never committed, supplied via an untracked *.auto.tfvars or environment. Unused while password auth is active (see providers.tf)."
  type        = string
  sensitive   = true
  default     = null
}

variable "proxmox_username" {
  description = "PVE username for password auth. LXC feature flags (keyctl) and device passthrough are root@pam-only checks that API tokens never satisfy, bootstrap must authenticate as root@pam with a password."
  type        = string
  default     = "root@pam"
}

variable "proxmox_password" {
  description = "Password for proxmox_username. Never committed, supplied via an untracked *.auto.tfvars."
  type        = string
  sensitive   = true
}

variable "proxmox_ssh_username" {
  description = "SSH username on the Proxmox host (for operations the API does not cover)"
  type        = string
  default     = "root"
}

variable "node_name" {
  description = "Proxmox node name that hosts the guests (node 1)"
  type        = string
  default     = "pve01"
}

variable "lxc_datastore" {
  description = "Datastore for LXC root filesystems"
  type        = string
  default     = "local-lvm"
}

variable "template_datastore" {
  description = "Datastore holding the LXC template and snippets"
  type        = string
  default     = "local"
}

variable "lxc_template_file_id" {
  description = "Volume ID of the Debian LXC template (e.g. local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst)"
  type        = string
  default     = "local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst"
}

variable "vm_datastore" {
  description = "Datastore for VM disks (root, EFI vars, cloud-init drive)"
  type        = string
  default     = "local-lvm"
}

variable "seed_image_url" {
  description = "Cloud image the NixOS VMs' disks are created from. It is only a seed, nixos-anywhere rewrites the disk during the install."
  type        = string
  default     = "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2"
}

variable "haos_image_file_id" {
  description = <<-EOT
    Volume ID of the Home Assistant OS disk image, staged on the node by
    scripts/haos-image.sh. Not downloaded by OpenTofu: HAOS publishes its qcow2
    only as `.xz`, which the provider cannot decompress (gz/lzo/zst/bz2 only).
    The `.img` extension is a rename of a real qcow2, PVE only accepts disk
    images on a directory store as `iso` content with an .img/.iso suffix.
  EOT
  type        = string
  default     = "local:iso/haos_ova-18.2.img"
}

variable "vm_public_key" {
  description = "SSH public key authorized for root on the seed image, the workstation key that runs nixos-anywhere, not the Ansible one: the install is driven by hand, and the installed system never reads this key again."
  type        = string
}

variable "bridge" {
  description = "VLAN-aware Linux bridge on the node"
  type        = string
  default     = "vmbr0"
}

variable "media_host_path" {
  description = "Host path of the 18 TB media disk, bind-mounted into media guests (path preserved from the pre-wipe layout)"
  type        = string
  default     = "/mnt/hdd"
}

variable "lxc_public_key" {
  description = "SSH public key installed in the containers for Ansible access"
  type        = string
}
