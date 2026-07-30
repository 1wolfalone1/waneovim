#!/usr/bin/env bash
# Read-only. Determines which physical disk holds the GRUB boot code,
# identifying disks by SERIAL (stable) rather than /dev/nvmeXn1 (not stable here).
set -uo pipefail

SYS_SERIAL=2404EE402177   # expected: /boot + /
OLD_SERIAL=2329BF403915   # expected: old /home, candidate for removal

[[ $EUID -eq 0 ]] || { echo "run as root"; exit 1; }

for dev in /dev/nvme0n1 /dev/nvme1n1; do
  [[ -b $dev ]] || continue
  serial=$(lsblk -dno SERIAL "$dev")
  case "$serial" in
    "$SYS_SERIAL") role="SYSTEM DISK (/boot + /)" ;;
    "$OLD_SERIAL") role="old /home - candidate for removal" ;;
    *)             role="UNKNOWN DISK" ;;
  esac

  echo "=============================================="
  echo " $dev   serial $serial"
  echo " role: $role"
  echo "=============================================="

  echo -n "  MBR bootcode: "
  if dd if="$dev" bs=512 count=1 status=none | strings -n 3 | grep -qi grub; then
    echo "GRUB PRESENT  <-- BIOS boots from this disk"
  else
    echo "no GRUB signature"
  fi

  echo -n "  boot signature (0x55AA): "
  sig=$(dd if="$dev" bs=1 skip=510 count=2 status=none | od -An -tx1 | tr -d ' \n')
  [[ $sig == 55aa ]] && echo "present" || echo "absent ($sig)"

  echo    "  partition table: $(lsblk -dno PTTYPE "$dev")"
  echo -n "  BIOS boot partition (needed for GPT+legacy GRUB): "
  sfdisk -l "$dev" 2>/dev/null | grep -qi "BIOS boot" && echo "yes" || echo "none"

  echo "  first-sector strings:"
  dd if="$dev" bs=512 count=1 status=none | strings -n 4 | head -5 | sed 's/^/      /'
  echo
done

echo "=============================================="
echo "VERDICT"
echo "=============================================="
echo "Safe to remove the old disk only if GRUB is PRESENT on serial $SYS_SERIAL"
echo "and ABSENT on serial $OLD_SERIAL. If GRUB shows up on the OLD disk,"
echo "stop - it must be reinstalled to the system disk before you pull anything:"
echo "    sudo grub-install --target=i386-pc /dev/disk/by-id/<system-disk-by-id>"
echo "    sudo grub-mkconfig -o /boot/grub/grub.cfg"
