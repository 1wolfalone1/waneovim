#!/usr/bin/env bash
# ENTRY POINT - run this from the Arch live USB, in the NEW AMD PC.
#
#     mkdir -p /usb && mount -L Ventoy /usb && bash /usb/MIGRATION/RUN-ME.sh
#
# It checks you are in the right machine and the right boot mode, then hands
# over to 05-uefi-convert.sh which does the actual work.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

confirm() {
  local ans=""
  [[ -r /dev/tty ]] && read -rp "$1 [y/N] " ans < /dev/tty || true
  [[ ${ans,,} == y || ${ans,,} == yes ]]
}

echo "=================================================="
echo " Arch migration - entry point"
echo "=================================================="
echo

[[ $EUID -eq 0 ]] || { echo "ERROR: run as root (you already are, in the live session)"; exit 1; }

# ---------------------------------------------------------------- environment
echo "==> where am I?"

# Live session, or the installed system by mistake? The archiso root is a
# squashfs/overlay; a real install is ext4. Running this from the installed
# system would try to convert the disk it is running from.
rootfs=$(findmnt -no FSTYPE / || true)
echo "    root filesystem : $rootfs"
if [[ $rootfs == ext4 ]]; then
  echo
  echo "    ERROR: this looks like the INSTALLED system, not the live USB."
  echo "    You cannot convert the disk you are booted from."
  echo "    Reboot, pick the Ventoy stick, then archlinux-x86_64.iso (UEFI)."
  exit 1
fi
echo "    ok - live session"

# ------------------------------------------------------------------ boot mode
if [[ -d /sys/firmware/efi ]]; then
  echo "    boot mode       : UEFI  ok"
else
  echo "    boot mode       : LEGACY/BIOS"
  echo
  echo "    ERROR: you booted the stick in legacy mode."
  echo "    Reboot, and at the boot menu pick the entry that starts with UEFI:"
  echo "    Without that, grub-install cannot register a UEFI boot entry."
  exit 1
fi

# ------------------------------------------------------------------- which PC
# The old machine is Intel, the new build is AMD Ryzen. If this is still the
# old PC, running the conversion would leave it unbootable for no reason.
vendor=$(grep -m1 '^vendor_id' /proc/cpuinfo | awk '{print $3}' || true)
model=$(grep -m1 '^model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ *//' || true)
echo "    cpu             : $model"

if [[ $vendor != AuthenticAMD ]]; then
  echo
  echo "    STOP: this CPU is '$vendor', not AMD."
  echo "    That means you are still in the OLD PC. Phase B is the step that"
  echo "    ends this machine's ability to boot - do not run it here."
  echo
  confirm "    Override? Only say yes if you are certain this is the new PC." \
    || { echo "    Aborted - nothing was changed."; exit 1; }
fi

# ------------------------------------------------------------------ hand over
echo
echo "==> disks seen by this live session:"
lsblk -o NAME,SIZE,FSTYPE,LABEL,SERIAL | sed 's/^/    /'
echo
echo "    Your Arch disk has serial 2404EE402177."
echo "    If it is NOT in the list above, stop and reseat it in the M.2 slot."
echo
confirm "==> Continue to the conversion?" || { echo "Aborted."; exit 1; }

# Copy to RAM first. The script must not be read off the USB while it runs,
# and exfat cannot set the exec bit anyway.
cp "$here/05-uefi-convert.sh" /root/
echo
exec bash /root/05-uefi-convert.sh
