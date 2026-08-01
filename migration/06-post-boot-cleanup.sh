#!/usr/bin/env bash
# Phase C - run this AFTER the new PC has booted to its desktop.
#
# Removes the NVIDIA driver stack and rebuilds the initramfs around the AMD
# hardware. None of this is needed to boot - which is exactly why it is not in
# Phase B. Doing it here means a mistake is recoverable: you have a working
# system, a shell, and (ideally) internet to reinstall anything.
#
# Safe to skip entirely. The machine runs fine on amdgpu with the NVIDIA
# packages still installed; they simply never load.
set -euo pipefail

BACKUP_DIR=/root/backup-cleanup-$(date +%Y%m%d-%H%M%S)

# linux-firmware-nvidia is deliberately NOT in this list. linux-firmware is a
# metapackage that hard-depends on every linux-firmware-* split package, so
# including it makes pacman reject the whole transaction and nothing at all
# gets removed. libva-nvidia-driver IS in the list because it depends on
# nvidia-utils and would block the removal otherwise.
NVIDIA_PKGS=(nvidia-open-dkms nvidia-utils lib32-nvidia-utils libva-nvidia-driver)

fail() { echo; echo "  ERROR: $*"; echo; exit 1; }
ok()   { printf '    ok    %s\n' "$*"; }

confirm() {
  local ans=""
  # Test that /dev/tty can actually be OPENED. `[[ -r /dev/tty ]]` only checks
  # the device node's permission bits and passes even with no controlling
  # terminal, which then makes the redirect fail noisily.
  if { exec 3</dev/tty; } 2>/dev/null; then
    read -rp "$1 [y/N] " ans <&3 || true
    exec 3<&-
  fi
  [[ ${ans,,} == y || ${ans,,} == yes ]]
}

[[ $EUID -eq 0 ]] || fail "run as root:  sudo bash $0"

echo "=============================================="
echo " Phase C - post-boot cleanup on the new PC"
echo "=============================================="
echo

# ------------------------------------------------------------------ 1. checks
echo "==> [1/4] checks"

if [[ -d /run/archiso ]]; then
  fail "this is the live USB. Run this from the installed system, after it boots."
fi
ok "running on the installed system"

# Removing the NVIDIA stack while it is the driver actually in use would take
# the desktop with it. Only proceed if amdgpu is already driving the machine.
if lspci -k 2>/dev/null | grep -A3 -iE 'VGA|3D controller' | grep -q 'Kernel driver in use: amdgpu'; then
  ok "amdgpu is the driver in use"
else
  echo
  echo "  amdgpu does not appear to be driving this machine:"
  lspci -k 2>/dev/null | grep -A3 -iE 'VGA|3D controller' | sed 's/^/    /'
  echo
  echo "  Removing the NVIDIA packages now could leave you without a display."
  confirm "  Continue anyway?" || fail "aborted - nothing was changed"
fi

if pacman -Q amd-ucode >/dev/null 2>&1; then ok "amd-ucode installed"; else
  echo "    WARNING: amd-ucode is not installed. Install it before rebooting:"
  echo "             sudo pacman -S amd-ucode"
fi

# mesa must provide opengl-driver and vulkan-radeon must provide vulkan-driver,
# or removing nvidia-utils leaves Hyprland with no GL implementation at all.
pacman -Q mesa >/dev/null 2>&1 || fail "mesa is not installed. Install it first: sudo pacman -S mesa"
pacman -Q vulkan-radeon >/dev/null 2>&1 || fail "vulkan-radeon is not installed. Install it first: sudo pacman -S vulkan-radeon"
ok "mesa and vulkan-radeon present (they replace what nvidia-utils provided)"
echo

# --------------------------------------------------------------- 2. dry run
echo "==> [2/4] what would be removed"

installed=()
for p in "${NVIDIA_PKGS[@]}"; do
  if pacman -Q "$p" >/dev/null 2>&1; then installed+=("$p"); fi
done

if (( ${#installed[@]} == 0 )); then
  echo "    none of the NVIDIA packages are installed - nothing to do"
  echo "    skipping to the initramfs rebuild"
else
  echo "    asking pacman exactly what it would remove:"
  if ! pacman -Rs --print --print-format '%n' "${installed[@]}" 2>&1 | sed 's/^/      /'; then
    echo
    echo "    pacman refused the transaction (output above)."
    echo "    Nothing was changed. Skipping removal and going straight to the"
    echo "    initramfs rebuild, which is harmless."
    installed=()
  fi
fi
echo

if (( ${#installed[@]} > 0 )); then
  echo "    Everything in that list is part of the NVIDIA stack. mesa keeps"
  echo "    providing opengl-driver and vulkan-radeon keeps providing"
  echo "    vulkan-driver, so Hyprland stays satisfied."
  echo
  confirm "    Remove them?" || { echo "    Skipped. Nothing was changed."; installed=(); }
  echo
fi

# ------------------------------------------------------------------ 3. remove
if (( ${#installed[@]} > 0 )); then
  echo "==> [3/4] removing"
  if pacman -Rs --noconfirm "${installed[@]}"; then
    ok "removed"
  else
    echo "    WARNING: removal failed. Nothing was removed and nothing is broken."
    echo "    The machine runs fine with these packages installed."
  fi
else
  echo "==> [3/4] removal skipped"
fi
echo

# -------------------------------------------------------- 4. initramfs + grub
echo "==> [4/4] rebuilding initramfs and grub.cfg"

mkdir -p "$BACKUP_DIR"
# Back up to /root, not /boot: /boot is a 1GB ESP and cannot hold a second copy
# of two 200MB+ images.
cp -a /boot/initramfs-linux.img /boot/initramfs-linux-lts.img "$BACKUP_DIR/" 2>/dev/null || true
cp -a /boot/grub/grub.cfg "$BACKUP_DIR/" 2>/dev/null || true
echo "    backups in $BACKUP_DIR"

if mkinitcpio -P; then
  ok "initramfs rebuilt"
else
  echo "    mkinitcpio reported errors."
  # Only claim a restore if there is actually something to restore from. An
  # unmatched glob would otherwise be passed to cp literally, fail silently
  # into `|| true`, and still print "restored".
  if compgen -G "$BACKUP_DIR/initramfs-*.img" >/dev/null; then
    cp -a "$BACKUP_DIR"/initramfs-*.img /boot/
    echo "    restored the images that got you here - do not reboot until you"
    echo "    know why it failed"
  else
    echo "    NO BACKUP EXISTS to restore from. Do not reboot until you have"
    echo "    checked /boot yourself."
  fi
fi

# mkinitcpio installs the image even when a hook failed, so a size check is
# worth more than 'is it non-empty'.
for img in /boot/initramfs-linux.img /boot/initramfs-linux-lts.img; do
  [[ -f $img ]] || { echo "    WARNING: $img is missing"; continue; }
  sz=$(stat -c%s "$img")
  if (( sz > 50000000 )); then
    printf '    %-38s %s  OK\n' "$img" "$(du -h "$img" | cut -f1)"
  else
    echo "    WARNING: $img is only $((sz/1024/1024))MB - suspiciously small."
    if [[ -f "$BACKUP_DIR/$(basename "$img")" ]]; then
      cp -a "$BACKUP_DIR/$(basename "$img")" /boot/
      echo "             restored from $BACKUP_DIR ($(du -h "$img" | cut -f1))"
    else
      echo "             NO BACKUP to restore from - check /boot before rebooting."
    fi
  fi
done

df -h /boot | tail -1 | sed 's/^/    /'

if grub-mkconfig -o /boot/grub/grub.cfg; then
  ok "grub.cfg written"
else
  echo "    WARNING: grub-mkconfig failed; restoring the previous grub.cfg"
  cp -a "$BACKUP_DIR/grub.cfg" /boot/grub/grub.cfg 2>/dev/null || true
fi

cat <<EOF

==============================================
 Phase C complete.
==============================================

Reboot when convenient, then check:

    lspci -k | grep -A3 VGA        # want: Kernel driver in use: amdgpu
    glxinfo | grep -i renderer     # want: AMD / RADV
    vulkaninfo --summary | head    # want: RADV

Backups: $BACKUP_DIR

If Hyprland misbehaves, the original NVIDIA settings are at
    ~/.config/hypr/nvidia.conf.nvidia-backup

Optional extras, now that you are on the new machine:

  - Add Windows to the GRUB menu (otherwise use the firmware boot menu):
        sudo sed -i 's/^#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
        sudo grub-mkconfig -o /boot/grub/grub.cfg

  - The old /home SSD (serial 2329BF403915) still holds a full 54GB copy of
    your home directory. Keep it until you are happy, then wipe or reuse it.
EOF
