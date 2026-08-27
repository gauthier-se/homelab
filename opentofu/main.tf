module "containers" {
  source   = "./modules/lxc-container"
  for_each = local.containers

  vm_id       = each.value.vm_id
  hostname    = each.key
  description = each.value.description
  node_name   = var.node_name
  tags        = each.value.tags

  cores     = try(each.value.cores, 1)
  memory    = try(each.value.memory, 512)
  swap      = try(each.value.swap, 512)
  disk_size = try(each.value.disk_size, 8)

  datastore_id     = var.lxc_datastore
  template_file_id = var.lxc_template_file_id

  unprivileged = try(each.value.unprivileged, true)
  nesting      = try(each.value.nesting, false)
  keyctl       = try(each.value.keyctl, false)
  start_order  = try(each.value.start_order, 3)

  bridge       = var.bridge
  vlan_id      = each.value.vlan_id
  ipv4_address = each.value.ipv4_address
  ipv4_gateway = each.value.ipv4_gateway
  nameservers  = each.value.nameservers
  public_key   = var.lxc_public_key

  mount_points       = try(each.value.mount_points, [])
  device_passthrough = try(each.value.device_passthrough, [])
}

# Seed image for the NixOS guests, downloaded to the node once. PVE only accepts
# disk images on a directory store under the `iso` content type, and only with an
# .img/.iso extension, hence the rename of a file that is really a qcow2.
#
# `tofu validate` warns that this resource type is deprecated in favour of the
# shorter `proxmox_download_file`. Left as is deliberately: every other resource
# here carries the same prefix, and the provider renames them all at v1.0:
# a one-line rename now would only make this file the odd one out.
resource "proxmox_virtual_environment_download_file" "seed_image" {
  node_name    = var.node_name
  datastore_id = var.template_datastore
  content_type = "iso"
  file_name    = "debian-13-genericcloud-amd64.img"
  url          = var.seed_image_url

  # Upstream republishes `latest` in place. Re-downloading it would change
  # nothing (the VMs' disks were rewritten by the installer long ago) and would
  # cost the node a few hundred megabytes on every apply.
  overwrite = false
}

module "vms" {
  source   = "./modules/nixos-vm"
  for_each = local.vms

  vm_id       = each.value.vm_id
  hostname    = each.key
  description = each.value.description
  node_name   = var.node_name
  tags        = each.value.tags

  cores     = try(each.value.cores, 2)
  memory    = try(each.value.memory, 2048)
  disk_size = try(each.value.disk_size, 32)

  datastore_id       = var.vm_datastore
  seed_image_file_id = proxmox_virtual_environment_download_file.seed_image.id
  start_order        = try(each.value.start_order, 3)

  bridge       = var.bridge
  vlan_id      = each.value.vlan_id
  ipv4_address = each.value.ipv4_address
  ipv4_gateway = each.value.ipv4_gateway
  nameservers  = each.value.nameservers
  public_key   = var.vm_public_key
}

# Home Assistant OS. The image is staged on the node by scripts/haos-image.sh
# rather than downloaded here: HAOS publishes its qcow2 only as `.xz`, and the
# provider's decompression covers gz/lzo/zst/bz2 only.
module "haos_vms" {
  source   = "./modules/haos-vm"
  for_each = local.haos_vms

  vm_id       = each.value.vm_id
  hostname    = each.key
  description = each.value.description
  node_name   = var.node_name
  tags        = each.value.tags

  cores     = try(each.value.cores, 2)
  memory    = try(each.value.memory, 4096)
  disk_size = try(each.value.disk_size, 32)

  datastore_id  = var.vm_datastore
  image_file_id = var.haos_image_file_id
  start_order   = try(each.value.start_order, 3)

  bridge  = var.bridge
  vlan_id = each.value.vlan_id
}
