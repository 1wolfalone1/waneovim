#!/usr/bin/env bash
# ENTRY POINT - run this from the Arch live USB, in the NEW AMD PC.
#
#     mkdir -p /usb && mount -L Ventoy /usb && bash /usb/MIGRATION/RUN-ME.sh
#
# It checks you are in the right machine, with the right disk, in the right
# boot mode, then hands over to 05-uefi-convert.sh which does the actual work.
# Every check here is cheap and happens before anything is written.
set -euo pipefail

ROOT_UUID=4776357f-67c6-4d1e-86aa-9ca39a1c6f85
BOOT_UUID=BA53-EA76
DISK_SERIAL=2404EE402177

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

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

echo "=================================================="
echo " Arch migration - entry point"
echo "=================================================="
echo

[[ $EUID -eq 0 ]] || fail "run as root (in the live session you already are)"

# ---------------------------------------------------------------- 1. where
echo "==> [1/4] where am I?"

# Positive test. The old version only rejected ext4, which would have passed
# on any non-ext4 installed system.
if [[ -d /run/archiso ]]; then
  ok "Arch live session"
else
  echo "    /run/archiso is absent - this does not look like the live USB."
  rootfs=$(findmnt -no FSTYPE / 2>/dev/null || true)
  echo "    root filesystem is: ${rootfs:-unknown}"
  if [[ $rootfs == ext4 ]]; then
    fail "this is the INSTALLED system, not the live USB.

  You cannot convert the disk you are booted from.
  Reboot, pick the Ventoy stick, then archlinux-x86_64.iso (UEFI)."
  fi
  confirm "    Continue anyway?" || fail "aborted - nothing was changed"
fi

if [[ -d /sys/firmware/efi ]]; then
  ok "booted in UEFI mode"
else
  fail "you booted the stick in LEGACY/BIOS mode.

  Reboot and at the boot menu pick the entry that starts with  UEFI:
  Without it, grub-install cannot register a UEFI boot entry.

  If there is no UEFI: entry, go into the BIOS and set:
      Secure Boot  -> Disabled
      CSM / Legacy -> Disabled"
fi
echo

# ------------------------------------------------------------------ 2. which PC
echo "==> [2/4] which machine is this?"

vendor=$(grep -m1 '^vendor_id' /proc/cpuinfo | awk '{print $3}' || true)
model=$(grep -m1 '^model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ *//' || true)
echo "    cpu: ${model:-unknown}"

# The old machine is Intel, the new build is AMD. Running Phase B in the old
# PC would destroy a working boot for no reason.
if [[ $vendor == AuthenticAMD ]]; then
  ok "AMD CPU - this is the new machine"
else
  echo
  echo "    STOP: this CPU reports '${vendor:-unknown}', not AMD."
  echo "    That means you are still in the OLD PC. Phase B is the step"
  echo "    that ends this machine's ability to boot - do not run it here."
  echo
  confirm "    Override? Only yes if you are certain this is the new PC." \
    || fail "aborted - nothing was changed"
fi
echo

# ------------------------------------------------------------------ 3. the disk
# The important one: prove the Arch disk is actually here, and is the disk
# holding this system, BEFORE handing over. A blank or unrelated SSD must stop
# the run here with a message that says what to do about it.
echo "==> [3/4] is the Arch disk present?"
udevadm settle 2>/dev/null || true

rootpart=$(blkid -U "$ROOT_UUID" 2>/dev/null || true)
bootpart=$(blkid -U "$BOOT_UUID" 2>/dev/null || true)

if [[ -z $rootpart || -z $bootpart ]]; then
  echo
  echo "    Disks this machine can see:"
  lsblk -o NAME,SIZE,FSTYPE,LABEL,SERIAL | sed 's/^/      /'
  echo
  [[ -n $rootpart ]] || echo "    NOT FOUND: root filesystem  $ROOT_UUID"
  [[ -n $bootpart ]] || echo "    NOT FOUND: boot filesystem  $BOOT_UUID"
  fail "the Arch disk is not here, or it is not the right disk.

  It is a WD Blue SN580 500GB, serial $DISK_SERIAL.

  If it is not in the list above:
    - power off completely
    - check the M.2 screw is holding the drive flat in its slot
    - move it to the M.2 slot nearest the CPU socket (usually M.2_1)
    - check the BIOS storage page can see the drive at all

  Nothing has been changed. It is safe to power off right now."
fi
ok "root filesystem found on $rootpart"
ok "boot filesystem found on $bootpart"

disk=/dev/$(lsblk -no PKNAME "$rootpart" | head -1)
[[ -b $disk ]] || fail "could not resolve the parent disk of $rootpart"

serial=$(lsblk -dno SERIAL "$disk" | tr -d ' ')
if [[ $serial == "$DISK_SERIAL" ]]; then
  ok "disk serial matches ($serial)"
else
  echo "    NOTE: disk serial is '$serial', expected '$DISK_SERIAL'."
  echo "    The filesystem UUIDs matched, which is the stronger test, so this"
  echo "    is probably just a cloned or replaced drive."
  confirm "    Continue?" || fail "aborted - nothing was changed"
fi
echo

# ------------------------------------------------------------------ 4. hand over
echo "==> [4/4] handing over to the conversion"
echo
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT,SERIAL | sed 's/^/    /'
echo
echo "    Target disk: $disk"
echo "    Nothing else is opened, written to, or even mounted."
echo
confirm "    Continue?" || fail "aborted - nothing was changed"

[[ -f "$here/05-uefi-convert.sh" ]] || fail "05-uefi-convert.sh is not next to this script (looked in $here)"

# Copy to RAM first: exfat cannot set the exec bit, and the script should not
# be read off the USB while it runs.
cp "$here/05-uefi-convert.sh" /root/
echo
exec bash /root/05-uefi-convert.sh
