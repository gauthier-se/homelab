variable "vm_id" {
  description = "Container VMID"
  type        = number
}

variable "hostname" {
  description = "Container hostname"
  type        = string
}

variable "description" {
  description = "Free-text description shown in the Proxmox UI"
  type        = string
  default     = "Managed by OpenTofu"
}

variable "node_name" {
  description = "Proxmox node hosting the container"
  type        = string
}

variable "tags" {
  description = "Proxmox tags (used for grouping in the UI and Ansible discovery)"
  type        = list(string)
  default     = []
}

variable "cores" {
  description = "CPU cores"
  type        = number
  default     = 1
}

variable "memory" {
  description = "RAM in MiB"
  type        = number
  default     = 512
}

variable "swap" {
  description = "Swap in MiB"
  type        = number
  default     = 512
}

variable "disk_size" {
  description = "Root filesystem size in GiB"
  type        = number
  default     = 8
}

variable "datastore_id" {
  description = "Datastore for the root filesystem"
  type        = string
}

variable "template_file_id" {
  description = "LXC template volume ID"
  type        = string
}

variable "unprivileged" {
  description = "Run as an unprivileged container"
  type        = bool
  default     = true
}

variable "nesting" {
  description = "Enable the nesting feature (required for containers that run Docker/systemd-nspawn)"
  type        = bool
  default     = false
}

variable "keyctl" {
  description = "Enable keyctl (required by some containerized workloads, e.g. Docker with certain storage drivers)"
  type        = bool
  default     = false
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
  description = "VLAN tag for the container's NIC"
  type        = number
}

variable "ipv4_address" {
  description = "Static IPv4 address in CIDR notation (e.g. 10.10.20.10/24)"
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
  description = "SSH public key for root inside the container"
  type        = string
}

variable "mount_points" {
  description = "Bind mounts from the host into the container (host path -> container path)"
  type = list(object({
    host_path      = string
    container_path = string
    read_only      = optional(bool, false)
  }))
  default = []
}

variable "device_passthrough" {
  description = <<-EOT
    Host devices to pass through. `gid` is the group that owns the device inside
    the container: without it the node hands the device over as root:root 0660,
    and a service running as its own user (Jellyfin, say) silently loses
    hardware acceleration. Set it to the container's `render`/`video` gid.
  EOT
  type = list(object({
    path = string
    gid  = optional(number)
    mode = optional(string)
  }))
  default = []
}
