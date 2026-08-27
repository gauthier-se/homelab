#!/usr/bin/env bash
# Verify the newest vzdump archive of every guest the backup jobs actually name.
#
# Runs ON the Proxmox node (/root/backup-verify.sh), from cron or by hand.
#
# ⚠️ It replaces a version that globbed a hard-coded date. Retention pruned
# those archives weeks later, after which the loop iterated over an unmatched
# glob, verified nothing, and reported success. Two lessons are wired in below:
#
#  - the guest list comes from /etc/pve/jobs.cfg, the same file that decides
#    what gets backed up, so the two cannot drift apart;
#  - a guest with no archive is a FAILURE, not a silent skip. That is the whole
#    class of bug this script existed to catch and did not.
#
# Exit code is non-zero if anything failed, so a cron wrapper can act on it.
set -uo pipefail

DUMPDIR="${DUMPDIR:-/mnt/backup1t/dump}"
JOBS="${JOBS:-/etc/pve/jobs.cfg}"

# Every VMID named by any vzdump job, deduplicated.
guests=$(awk '/^\tvmid /{gsub(/,/," ",$2); print $2}' "$JOBS" | tr ' ' '\n' | sort -un)

if [ -z "$guests" ]; then
  echo "FAIL  no vmid found in $JOBS - refusing to report success"
  exit 2
fi

rc=0
checked=0
failures=""
for id in $guests; do
  # LXC archives are .tar.zst, VMs are .vma.zst; sort by name, which is the
  # timestamp, and take the newest.
  latest=$(ls -1 "$DUMPDIR"/vzdump-*-"$id"-*.zst 2>/dev/null | sort | tail -1)
  if [ -z "$latest" ]; then
    echo "FAIL  $id  no archive at all in $DUMPDIR"
    failures="$failures\nFAIL $id: no archive at all"
    rc=1
    continue
  fi
  age_days=$(( ( $(date +%s) - $(stat -c %Y "$latest") ) / 86400 ))
  if zstd -t "$latest" 2>/dev/null; then
    printf 'OK    %-4s %s (%s day(s) old)\n' "$id" "$(basename "$latest")" "$age_days"
  else
    printf 'FAIL  %-4s %s corrupt\n' "$id" "$(basename "$latest")"
    failures="$failures\nFAIL $id: archive corrupt"
    rc=1
  fi
  # An archive that verifies but is a fortnight old is a job that stopped
  # running, which reads exactly like a healthy backup from here.
  if [ "$age_days" -gt 2 ]; then
    printf 'FAIL  %-4s newest archive is %s days old - the job is not running\n' "$id" "$age_days"
    failures="$failures\nFAIL $id: newest archive is $age_days days old"
    rc=1
  fi
  checked=$((checked + 1))
done

echo "--- $checked guest(s) checked, exit $rc ---"

# A weekly timer nobody reads is the same problem one layer up, so failures go to
# the phone, on the topic Proxmox and Uptime Kuma already use. Read from the
# notification config rather than stored a second time here.
if [ "$rc" -ne 0 ]; then
  url=$(awk '/^webhook: ntfy$/{f=1} f && /^\turl /{print $2; exit}' \
    /etc/pve/notifications.cfg 2>/dev/null)
  # ASCII only in headers: an em dash once broke every Proxmox notification.
  [ -n "$url" ] && curl -sS --max-time 20 \
    -H "Title: Backup verification FAILED" -H "Priority: 5" \
    -d "$(printf '%b' "$failures")" "$url" >/dev/null 2>&1
fi

exit $rc
