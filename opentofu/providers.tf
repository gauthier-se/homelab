provider "proxmox" {
  endpoint = var.proxmox_endpoint

  # Password auth as root@pam: PVE gates LXC feature flags (keyctl, …) and
  # device passthrough behind root@pam proper, an API token, even root's,
  # fails those checks. Token auth (var.proxmox_api_token) can return once
  # the catalogue no longer needs root-only attributes.
  username = var.proxmox_username
  password = var.proxmox_password

  # Self-signed PVE certificate until the OpenBao PKI fronts it.
  insecure = true

  ssh {
    agent    = true
    username = var.proxmox_ssh_username
  }
}
