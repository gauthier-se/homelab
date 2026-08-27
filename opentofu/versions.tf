terraform {
  required_version = ">= 1.8.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.60.0"
    }
  }

  # Local state, untracked, and ⚠️ NOT backed up by anything: the offsite job
  # covers the node, and this file lives on the workstation. It holds every
  # input in plaintext, `proxmox_password` included.
  #
  # Target: S3-compatible remote backend (Cloudflare R2) with state locking, and
  # state encryption decided before that move, not after.
}
