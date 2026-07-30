#!/usr/bin/env bash
# Phase 2 (run AFTER reboot, as root):
#   Verifies /home now lives on the root disk, then syncs any files that
#   changed on the old disk during the phase-1 copy window.
#   Uses --update and no --delete: files newer on the new /home are never
#   overwritten and nothing is removed. Safe before or after a desktop login.
set -euo pipefail

OLD_UUID=34624526-36a5-4729-b266-350b5483acc1
OLD=/mnt/oldhome
LOG=$(mktemp)

[[ $EUID -eq 0 ]] || { echo "run as root"; exit 1; }

confirm() {   # reads the terminal directly; defaults to NO if there is no tty
  local ans=""
  [[ -r /dev/tty ]] && read -rp "$1 [y/N] " ans < /dev/tty || true
  [[ ${ans,,} == y || ${ans,,} == yes ]]
}

echo "==> /home must NOT be a separate mount anymore"
if findmnt -n /home > /dev/null; then
  echo "ERROR: /home is still mounted separately:"; findmnt /home; exit 1
fi
echo "    ok - /home is on $(findmnt -n -o SOURCE /)"

echo "==> mounting the old disk read-only at $OLD"
mkdir -p "$OLD"
mountpoint -q "$OLD" || mount -o ro "UUID=$OLD_UUID" "$OLD"
unmount_old() { umount "$OLD" 2>/dev/null || true; rmdir "$OLD" 2>/dev/null || true; rm -f "$LOG"; }
trap unmount_old EXIT

# NOTE: write to a file rather than piping into head. Piping into head under
# `set -o pipefail` makes rsync die of SIGPIPE (141) and aborts the script.
echo "==> dry run: what changed on the old disk during the copy window"
rsync -aHAXxu --numeric-ids -n --itemize-changes \
      --exclude 'lost+found' "$OLD/" /home/ > "$LOG" || true
changed=$(wc -l < "$LOG")
echo "    $changed path(s) would be updated. First 60:"
head -60 "$LOG"
[[ $changed -gt 60 ]] && echo "    ... full list: $LOG (deleted when this script exits)" || true

if [[ $changed -eq 0 ]]; then
  echo "    nothing to do - the copy is already identical."
else
  confirm "Apply these updates?" || { echo "Skipped."; exit 0; }
  rsync -aHAXxu --numeric-ids --info=progress2 \
        --exclude 'lost+found' "$OLD/" /home/
fi

echo "==> size comparison (old disk vs new /home)"
du -sx "$OLD" /home

echo
echo "Done. Use the machine normally for a few days."
echo "When you are sure nothing is missing, free the old disk with:"
echo "    sudo wipefs -a /dev/nvme1n1"
echo "then power off and pull nvme1n1."
