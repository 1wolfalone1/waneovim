#!/usr/bin/env bash
# Phase B - run this from the ARCH LIVE USB, in the NEW PC.
#
# Converts this Arch install from legacy-BIOS booting to UEFI booting,
# and swaps the graphics stack from NVIDIA to AMD.
#
# Your files are NOT touched. This rewrites the partition TABLE (the index
# at the start of the disk) and installs a bootloader. No filesystem is
# formatted, no data is erased.
#
# Requires: booted from the Ventoy stick -> archlinux-x86_64.iso -> UEFI entry
# Needs no internet.
set -euo pipefail

ROOT_UUID=4776357f-67c6-4d1e-86aa-9ca39a1c6f85   # your /
BOOT_UUID=BA53-EA76                              # your /boot (becomes the ESP)

confirm() {
  local ans=""
  [[ -r /dev/tty ]] && read -rp "$1 [y/N] " ans < /dev/tty || true
  [[ ${ans,,} == y || ${ans,,} == yes ]]
}

[[ $EUID -eq 0 ]] || { echo "run as root"; exit 1; }

echo "=============================================="
echo " Phase B - BIOS -> UEFI conversion"
echo "=============================================="
echo

# ------------------------------------------------------------ 1. sanity checks
echo "==> [1/6] checks"

if [[ ! -d /sys/firmware/efi ]]; then
  echo "  ERROR: this live session booted in LEGACY/BIOS mode, not UEFI."
  echo "  Reboot and pick the UEFI entry for the Arch ISO in Ventoy,"
  echo "  otherwise grub-install cannot register a UEFI boot entry."
  exit 1
fi
echo "  ok - live session is in UEFI mode"

rootpart=$(blkid -U "$ROOT_UUID" 2>/dev/null || true)
bootpart=$(blkid -U "$BOOT_UUID" 2>/dev/null || true)
[[ -n $rootpart ]] || { echo "  ERROR: cannot find root UUID $ROOT_UUID"; exit 1; }
[[ -n $bootpart ]] || { echo "  ERROR: cannot find boot UUID $BOOT_UUID"; exit 1; }

disk=/dev/$(lsblk -no PKNAME "$rootpart")
echo "  root partition : $rootpart"
echo "  boot partition : $bootpart"
echo "  target disk    : $disk"

# Both partitions must live on the SAME disk, or we are looking at the wrong one
[[ "/dev/$(lsblk -no PKNAME "$bootpart")" == "$disk" ]] || {
  echo "  ERROR: root and boot are on different disks. Aborting."; exit 1; }

echo
echo "  Disks present in this machine:"
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT | sed 's/^/    /'
echo
echo "  ONLY $disk will be modified. Any Windows disk is untouched."
confirm "  Proceed?" || { echo "Aborted."; exit 1; }

# ------------------------------------------------------- 2. unmount everything
echo
echo "==> [2/6] making sure nothing on $disk is mounted"
umount -R /mnt 2>/dev/null || true
for p in "$rootpart" "$bootpart"; do
  umount "$p" 2>/dev/null || true
done
if findmnt -S "$rootpart" >/dev/null || findmnt -S "$bootpart" >/dev/null; then
  echo "  ERROR: still mounted. Aborting."; exit 1
fi
echo "  ok - unmounted"

# ----------------------------------------------------------- 3. MBR -> GPT
echo
echo "==> [3/6] converting partition table MBR -> GPT"
echo "  current: $(lsblk -dno PTTYPE "$disk")"
sgdisk -g "$disk"
partprobe "$disk" 2>/dev/null || true
sleep 2
new_pt=$(lsblk -dno PTTYPE "$disk")
echo "  now    : $new_pt"
[[ $new_pt == gpt ]] || { echo "  ERROR: conversion failed. Aborting."; exit 1; }

echo
echo "==> marking ${bootpart} as an EFI System Partition"
# Read the partition number from sysfs rather than parsing the device name.
# ${bootpart##*p} works for /dev/nvme0n1p1 but returns the whole path for
# /dev/sda1 (no 'p' to strip), which would feed sgdisk a nonsense argument.
partnum=$(cat "/sys/class/block/$(basename "$bootpart")/partition" 2>/dev/null || true)
[[ $partnum =~ ^[0-9]+$ ]] || {
  echo "  ERROR: could not determine partition number for $bootpart"; exit 1; }
echo "  partition number: $partnum"
sgdisk -t "${partnum}":EF00 "$disk"
partprobe "$disk" 2>/dev/null || true
sleep 2
sgdisk -p "$disk" | sed 's/^/  /'

# ---------------------------------------------------------------- 4. mount
echo
echo "==> [4/6] mounting your system at /mnt"
mount "$rootpart" /mnt
mount "$bootpart" /mnt/boot
findmnt -R /mnt | sed 's/^/  /'

# -------------------------------------------------------- 5. UEFI bootloader
echo
echo "==> [5/6] installing UEFI GRUB (the critical step)"
arch-chroot /mnt /bin/bash <<'CHROOT'
set -euo pipefail
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Arch --recheck
echo "  registered UEFI entry 'Arch'"

# Second copy at the firmware fallback path \EFI\BOOT\BOOTX64.EFI. Every UEFI
# board checks there when no NVRAM entry matches - so the disk still boots
# after a CMOS reset, or in a board that drops unknown NVRAM entries.
grub-install --target=x86_64-efi --efi-directory=/boot --removable --recheck
echo "  installed fallback copy at EFI/BOOT/BOOTX64.EFI"

echo "  EFI directory now contains:"
ls -R /boot/EFI/ 2>/dev/null | sed 's/^/    /' || true

[[ -f /boot/EFI/BOOT/BOOTX64.EFI ]] || { echo "  ERROR: fallback loader missing"; exit 1; }
CHROOT

# ------------------------------------------------- 6. NVIDIA -> AMD switchover
echo
echo "==> [6/6] switching graphics stack NVIDIA -> AMD"
arch-chroot /mnt /bin/bash <<'CHROOT'
set -uo pipefail   # NOT -e: a failure here must not abort after grub succeeded

echo "  removing nvidia_drm.modeset=1 from kernel cmdline"
cp -a /etc/default/grub /etc/default/grub.bak
sed -i 's/ *nvidia_drm\.modeset=1//' /etc/default/grub
grep '^GRUB_CMDLINE_LINUX_DEFAULT' /etc/default/grub | sed 's/^/    /'

echo "  removing NVIDIA packages"
if pacman -Rns --noconfirm nvidia-open-dkms nvidia-utils lib32-nvidia-utils \
                           libva-nvidia-driver linux-firmware-nvidia; then
  echo "    removed"
else
  echo "    WARNING: removal failed. Not fatal - the system still boots and"
  echo "    amdgpu will be used. Clean up later with:"
  echo "      sudo pacman -Rns nvidia-open-dkms nvidia-utils lib32-nvidia-utils"
fi

echo "  neutralising Hyprland's NVIDIA config"
NV=/home/thiencn/.config/hypr/nvidia.conf
if [[ -f $NV ]]; then
  cp -a "$NV" "$NV.nvidia-backup"
  # keep the file (it is 'source'd) but comment out every directive
  sed -i 's/^\([^#[:space:]]\)/# \1/' "$NV"
  chown thiencn:thiencn "$NV" "$NV.nvidia-backup"
  echo "    commented out; original kept at $NV.nvidia-backup"
fi

echo "  rebuilding initramfs and grub.cfg"
echo "    /boot space before:"
df -h /boot | tail -1 | sed 's/^/      /'

if mkinitcpio -P; then
  echo "    initramfs rebuilt"
else
  echo "    ERROR: mkinitcpio failed - /boot may be full."
  echo "    The images may be incomplete. Check before rebooting:"
  df -h /boot | tail -1 | sed 's/^/      /'
fi

# A truncated initramfs is unbootable, so verify each one is non-empty.
for img in /boot/initramfs-*.img; do
  [[ -s $img ]] && printf '    %-34s %s\n' "$img" "$(du -h "$img" | cut -f1)" \
                || echo "    WARNING: $img is EMPTY"
done

grub-mkconfig -o /boot/grub/grub.cfg
[[ -s /boot/grub/grub.cfg ]] && echo "    grub.cfg written" \
                             || echo "    WARNING: grub.cfg is empty"
CHROOT

# ------------------------------------------------------------------ finish
echo
echo "==> unmounting"
sync
if ! umount -R /mnt; then
  echo "  WARNING: /mnt would not unmount cleanly."
  echo "  Run 'sync' then power off from the menu - do NOT pull the plug."
fi

cat <<EOF

==============================================
 Phase B complete.
==============================================

Now: shut down, REMOVE THE USB STICK, and power on.

If the PC boots straight into Windows instead of Arch, that is not a
failure - press the boot menu key (F8 / F11 / F12) and pick the entry
named "Arch". Then set it first in the BIOS boot order.

After you reach the desktop, check the AMD card is driving it:
    lspci -k | grep -A3 VGA        # should say 'Kernel driver in use: amdgpu'
    glxinfo | grep -i renderer     # should mention AMD / RADV

If Hyprland misbehaves, the old NVIDIA settings are at
/home/thiencn/.config/hypr/nvidia.conf.nvidia-backup
EOF
