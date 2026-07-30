#!/usr/bin/env bash
# Phase 1 (run BEFORE reboot, as root):
#   Copies the live /home (nvme1n1p1) onto the root filesystem (nvme0n1p2),
#   then disables the /home mount in /etc/fstab.
# The old disk is NOT touched. Nothing on nvme1n1 is deleted.
set -euo pipefail

OLD_UUID=34624526-36a5-4729-b266-350b5483acc1   # nvme1n1p1, currently /home
BIND=/mnt/rootfs

[[ $EUID -eq 0 ]] || { echo "run as root"; exit 1; }

confirm() {   # reads the terminal directly; defaults to NO if there is no tty
  local ans=""
  [[ -r /dev/tty ]] && read -rp "$1 [y/N] " ans < /dev/tty || true
  [[ ${ans,,} == y || ${ans,,} == yes ]]
}

echo "==> sanity checks"
findmnt -n /home | grep -q 'nvme1n1p1' || {
  echo "ERROR: /home is not the expected nvme1n1p1 mount. Aborting."; exit 1; }

need=$(du -sx --block-size=1G /home 2>/dev/null | cut -f1 || echo 0)
free=$(df --output=avail --block-size=1G / | tail -1 | tr -d ' ')
echo "    /home needs ~${need}G, / has ${free}G free"
[[ $need -gt 0 ]] || { echo "ERROR: could not measure /home. Aborting."; exit 1; }
(( free > need + 10 )) || { echo "ERROR: not enough room on /. Aborting."; exit 1; }

echo "==> bind-mounting / at $BIND to reach the real /home dir on nvme0n1p2"
mkdir -p "$BIND"
mountpoint -q "$BIND" || mount --bind / "$BIND"
mountpoint -q "$BIND" || { echo "ERROR: bind mount failed. Aborting."; exit 1; }
cleanup() { umount "$BIND" 2>/dev/null || true; rmdir "$BIND" 2>/dev/null || true; }
trap cleanup EXIT

# The bind target MUST be the shadowed /home dir, i.e. a different device than /home.
# Without this check a --delete rsync could target /home itself.
[[ "$(stat -c %d "$BIND/home")" != "$(stat -c %d /home)" ]] || {
  echo "ERROR: $BIND/home is the same filesystem as /home. Aborting."; exit 1; }

# fstab shows /home once lived on another UUID, so the shadowed dir may hold
# leftovers. rsync --delete would erase them, so look before touching anything.
echo "==> inspecting the destination (shadowed /home on nvme0n1p2)"
if [[ -n "$(ls -A "$BIND/home" 2>/dev/null)" ]]; then
  echo "    NOT EMPTY - it currently contains:"
  ls -la "$BIND/home"
  du -sh "$BIND/home" 2>/dev/null || true
  echo
  echo "    The copy runs with --delete, so anything above that is not in the"
  echo "    live /home will be REMOVED. Inspect it first if you don't recognise it."
  confirm "    Proceed and let --delete remove it?" || { echo "Aborted."; exit 1; }
else
  echo "    empty - good"
fi

echo "==> rsync (this is the long part)"
rsync -aHAXx --numeric-ids --delete --info=progress2 \
      --exclude 'lost+found' \
      /home/ "$BIND/home/"

echo "==> size comparison (source vs copy)"
du -sx /home "$BIND/home"

echo "==> backing up and editing /etc/fstab"
cp -a /etc/fstab "/etc/fstab.bak.$(date +%Y%m%d-%H%M%S)"
sed -i "s|^\(UUID=$OLD_UUID\s.*\)|# disabled $(date +%F): /home moved to nvme0n1p2\n#\1|" /etc/fstab
echo "    /home-related lines in fstab now:"
grep -n 'home' /etc/fstab

echo
echo "DONE. /home now also exists on the root disk, and fstab will no longer"
echo "mount nvme1n1p1 at boot. The old disk still holds an intact copy."
echo
echo "Next: reboot, then run 02-post-reboot-verify.sh"
