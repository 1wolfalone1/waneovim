#!/usr/bin/env bash
# Phase A - SAFE PREP for moving this disk to the new AMD PC.
#
# This script does NOT break the current machine. After running it this PC
# still boots normally (legacy BIOS, NVIDIA, Intel) exactly as before.
# It only ADDS the pieces the new hardware will need.
#
#   1. installs amd-ucode, vulkan-radeon, lib32-vulkan-radeon, efibootmgr, gptfdisk
#   2. removes 'autodetect' from mkinitcpio HOOKS so the initramfs carries
#      drivers for ANY hardware, not just this machine's
#   3. regenerates initramfs and grub.cfg
#
# Nothing NVIDIA is removed here - that happens in Phase B, on the new PC,
# because removing it now would take Hyprland with it.
set -euo pipefail

BOOT_MIN_FREE_MB=250
BACKUP_DIR=/var/backup-prep-$(date +%Y%m%d-%H%M%S)

[[ $EUID -eq 0 ]] || { echo "run as root"; exit 1; }

confirm() {   # reads the terminal directly; defaults to NO if there is no tty
  local ans=""
  [[ -r /dev/tty ]] && read -rp "$1 [y/N] " ans < /dev/tty || true
  [[ ${ans,,} == y || ${ans,,} == yes ]]
}

echo "=============================================="
echo " Phase A - safe prep. This PC keeps working."
echo "=============================================="
echo

# ---------------------------------------------------------------- 1. packages
echo "==> [1/4] installing packages the AMD hardware will need"

# A stale sync database lists package versions the mirrors have already
# deleted, so every download 404s. Catch that here and say so plainly,
# instead of letting pacman emit a wall of mirror errors.
newest_db=$(find /var/lib/pacman/sync -name '*.db' -printf '%T@\n' 2>/dev/null | sort -rn | head -1)
if [[ -n $newest_db ]]; then
  age_days=$(( ( $(date +%s) - ${newest_db%.*} ) / 86400 ))
  echo "    pacman database last synced ${age_days} day(s) ago"
  if (( age_days > 14 )); then
    cat <<EOF

    ------------------------------------------------------------------
    STOP: the package database is ${age_days} days old.

    It still lists versions the mirrors have deleted, so downloads will
    fail with 404 errors. This is not a mirror problem.

    Fix it first, in this order:

        sudo pacman -Sy archlinux-keyring
        sudo pacman -Syu

    The keyring goes first, or signature checks on newer packages fail.
    A kernel update is likely - REBOOT afterwards, then run this script
    again.

    Do NOT try 'pacman -Sy' plus installing these packages on its own.
    That is a partial upgrade and is a known way to break Arch.
    ------------------------------------------------------------------

EOF
    exit 1
  fi
fi

if ! pacman -S --needed --noconfirm amd-ucode vulkan-radeon lib32-vulkan-radeon \
                                    efibootmgr gptfdisk; then
  echo
  echo "    Package installation failed - nothing on this system was changed."
  echo "    If the errors above are 404s, run 'sudo pacman -Syu' and retry."
  exit 1
fi
echo "    installed. intel-ucode is kept too - they do not conflict."
echo

# ------------------------------------------------------------- 2. backups
echo "==> [2/4] backing up config and current initramfs to $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"
cp -a /etc/mkinitcpio.conf "$BACKUP_DIR/"
cp -a /boot/initramfs-*.img "$BACKUP_DIR/" 2>/dev/null || true
cp -a /boot/grub/grub.cfg "$BACKUP_DIR/" 2>/dev/null || true
ls -la "$BACKUP_DIR"
echo

# --------------------------------------------------------- 3. mkinitcpio hooks
echo "==> [3/4] removing 'autodetect' from mkinitcpio HOOKS"
echo "    before: $(grep '^HOOKS' /etc/mkinitcpio.conf)"

if grep -q '^HOOKS=.*[( ]autodetect[ )]' /etc/mkinitcpio.conf; then
  sed -i 's/^\(HOOKS=(.*\)\ autodetect\(.*\)$/\1\2/' /etc/mkinitcpio.conf
  echo "    after : $(grep '^HOOKS' /etc/mkinitcpio.conf)"
else
  echo "    already absent - nothing to do"
fi

# Without autodetect the images get bigger. /boot is only 1G, so check first.
free_mb=$(df --output=avail -m /boot | tail -1 | tr -d ' ')
echo "    /boot free before rebuild: ${free_mb}MB"
if (( free_mb < BOOT_MIN_FREE_MB )); then
  echo "    WARNING: /boot has less than ${BOOT_MIN_FREE_MB}MB free."
  confirm "    Continue anyway?" || {
    echo "    Aborted. Restoring mkinitcpio.conf."
    cp -a "$BACKUP_DIR/mkinitcpio.conf" /etc/mkinitcpio.conf
    exit 1; }
fi
echo

# ------------------------------------------------------ 4. rebuild initramfs
echo "==> [4/4] rebuilding initramfs (slow - images will be noticeably larger)"
if ! mkinitcpio -P; then
  echo
  echo "    mkinitcpio FAILED. Restoring the previous config and images."
  cp -a "$BACKUP_DIR/mkinitcpio.conf" /etc/mkinitcpio.conf
  cp -a "$BACKUP_DIR"/initramfs-*.img /boot/ 2>/dev/null || true
  echo "    Restored. This machine still boots. Nothing lost."
  exit 1
fi

echo
echo "==> verifying"
for img in /boot/initramfs-linux.img /boot/initramfs-linux-lts.img; do
  if [[ -s $img ]]; then
    printf '    %-38s %s  OK\n' "$img" "$(du -h "$img" | cut -f1)"
  else
    echo "    $img MISSING OR EMPTY - restoring backups"
    cp -a "$BACKUP_DIR"/initramfs-*.img /boot/
    exit 1
  fi
done

df -h /boot | tail -1 | sed 's/^/    /'

echo
echo "==> regenerating grub.cfg (picks up amd-ucode for the new CPU)"
grub-mkconfig -o /boot/grub/grub.cfg
echo
echo "    microcode images referenced in grub.cfg:"
# NOTE: || true is required. With `set -o pipefail`, a grep that matches
# nothing returns 1 and would kill the script right before the success message.
grep -o '/[a-z-]*-ucode\.img' /boot/grub/grub.cfg | sort -u | sed 's/^/      /' || true

cat <<EOF

==============================================
 Phase A complete.
==============================================

This PC is UNCHANGED in how it boots. Legacy BIOS, NVIDIA and Intel all
still work. Backups are in:
    $BACKUP_DIR

NEXT STEP - reboot now and confirm this machine still comes up normally.
Do that BEFORE going anywhere near Phase B. If it does not boot, at the
GRUB menu pick the other kernel, or restore from the backup directory.

Phase B (GPT conversion, UEFI GRUB, NVIDIA removal) happens LATER, on the
new PC, booted from the Ventoy stick. It is the step that ends this
machine's ability to boot - do not run it until the new PC is built.
EOF
