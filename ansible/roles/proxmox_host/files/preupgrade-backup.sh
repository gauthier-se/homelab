#!/usr/bin/env bash
# Take a fresh backup of every guest, right before a Proxmox or kernel upgrade.
#
# Runs ON the Proxmox node (/root/preupgrade-backup.sh).
#
# ⚠️ It replaces a version that hard-coded a list of guest IDs. Every guest
# created after it was written was skipped, so the script that exists to make
# an upgrade reversible quietly left the newest services out of it.
#
# The fix is to stop keeping a list: both batches are read from /etc/pve/jobs.cfg,
# which is where the guest-to-mode decision genuinely lives. `snapshot` is free
# but Proxmox refuses it on any container carrying a bind mount, so those guests
# need `suspend` and its few seconds of freeze.
#
# Usage:  preupgrade-backup.sh "PVE 9.2.10 kernel 7.0.14-12"
set -uo pipefail

NOTE="${1:-manual pre-upgrade backup}"
JOBS="${JOBS:-/etc/pve/jobs.cfg}"
STORAGE="${STORAGE:-backup1t}"

# Pair each job's mode with its vmid list, in file order.
mapfile -t modes < <(awk '/^\tmode /{print $2}' "$JOBS")
mapfile -t lists < <(awk '/^\tvmid /{print $2}' "$JOBS")

if [ "${#modes[@]}" -eq 0 ] || [ "${#modes[@]}" -ne "${#lists[@]}" ]; then
  echo "FAIL  could not pair modes and vmid lists in $JOBS - refusing to guess"
  exit 2
fi

rc=0
for i in "${!modes[@]}"; do
  mode="${modes[$i]}"
  vmids="${lists[$i]//,/ }"
  echo "--- batch $((i + 1)): mode $mode, guests $vmids ---"
  # shellcheck disable=SC2086
  vzdump $vmids --storage "$STORAGE" --mode "$mode" --compress zstd \
    --notes-template "$NOTE"
  batch_rc=$?
  echo "rc batch $((i + 1))=$batch_rc"
  [ "$batch_rc" -eq 0 ] || rc=1
done

exit $rc
