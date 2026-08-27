#!/usr/bin/env bash
# Stage the Home Assistant OS disk image on the Proxmox node.
#
# OpenTofu cannot do this itself: HAOS publishes its qcow2 only as `.xz`, and
# proxmox_virtual_environment_download_file decompresses gz/lzo/zst/bz2 only.
# The result is renamed to `.img` because PVE accepts disk images on a directory
# store as `iso` content with an .img/.iso suffix, the same rename the Debian
# seed image gets in opentofu/main.tf.
#
# Idempotent: does nothing if the image is already staged.
#
# Usage:  scripts/haos-image.sh [version]      # default: latest release
set -euo pipefail

NODE="${HAOS_NODE:-10.10.10.3}"
SSH_KEY="${HAOS_SSH_KEY:-$HOME/.ssh/homelab-ansible}"
DEST_DIR="${HAOS_DEST_DIR:-/var/lib/vz/template/iso}"

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "→ resolving the latest HAOS release…"
  VERSION="$(curl -fsSL https://api.github.com/repos/home-assistant/operating-system/releases/latest \
             | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p')"
fi
[[ -n "$VERSION" ]] || { echo "could not resolve the HAOS version" >&2; exit 1; }

URL="https://github.com/home-assistant/operating-system/releases/download/${VERSION}/haos_ova-${VERSION}.qcow2.xz"
IMG="haos_ova-${VERSION}.img"

echo "→ version : ${VERSION}"
echo "→ node    : ${NODE}:${DEST_DIR}/${IMG}"
echo
echo "⚠️  Changing version means aligning the default of haos_image_file_id in"
echo "    opentofu/variables.tf, but do NOT apply to update a VM that is"
echo "    already installed: the image IS the system, and the module ignores"
echo "    disk[0].file_id on purpose so that a new file cannot schedule the"
echo "    replacement of a live VM. HAOS updates itself from its own UI."
echo

ssh -i "$SSH_KEY" -o BatchMode=yes "root@${NODE}" bash -seu <<EOF
  dest="${DEST_DIR}/${IMG}"
  if [ -f "\$dest" ]; then
    echo "already staged: $dest ($(du -h "$dest" | cut -f1)), nothing to do"
    exit 0
  fi
  command -v xz >/dev/null || { echo "xz missing on the node: apt install -y xz-utils" >&2; exit 1; }
  mkdir -p "${DEST_DIR}"
  tmp="\$(mktemp -d)"
  trap 'rm -rf "\$tmp"' EXIT
  echo "downloading…"
  curl -fL --progress-bar -o "\$tmp/haos.qcow2.xz" "${URL}"
  echo "decompressing…"
  xz -d "\$tmp/haos.qcow2.xz"
  # Atomic write: a concurrent apply must never see a partial file.
  mv "\$tmp/haos.qcow2" "\$dest.partial"
  mv "\$dest.partial" "\$dest"
  echo "staged: \$dest (\$(du -h "\$dest" | cut -f1))"
EOF

echo
echo "✅ Image in place. Check that opentofu/variables.tf points at:"
echo "   local:iso/${IMG}"
