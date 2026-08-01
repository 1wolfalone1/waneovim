#!/usr/bin/env bash
# Phase B - run this from the ARCH LIVE USB, in the NEW PC.
#
# Converts this Arch install from legacy-BIOS booting to UEFI booting.
#
# Your files are NOT touched. This rewrites the partition TABLE (the index at
# the start of the disk) and installs a bootloader. No filesystem is formatted,
# no data is erased.
#
# SCOPE: this script does ONLY what is required to make the disk boot on the
# new board. It deliberately does NOT remove NVIDIA packages and does NOT
# rebuild the initramfs. Both are done by 06-post-boot-cleanup.sh once the new
# machine is up and has internet. Doing them here, offline, with no way to
# reinstall a package, is risk with no boot-time benefit.
#
# Requires: booted from the Ventoy stick -> archlinux-x86_64.iso -> UEFI entry
# Needs no internet.
set -euo pipefail

ROOT_UUID=4776357f-67c6-4d1e-86aa-9ca39a1c6f85   # your /
BOOT_UUID=BA53-EA76                              # your /boot (becomes the ESP)
EXPECT_HOSTNAME=""                               # filled in below from the disk
MIN_ESP_FREE_MB=32
GPT_TAIL_SECTORS=33                              # backup GPT header + table

# Set to 1 the moment the partition table is rewritten. Until then every exit
# path is harmless; after it, a failure needs a specific recovery message.
DESTRUCTIVE=0

fail() { echo; echo "  ERROR: $*"; echo; exit 1; }
ok()   { printf '    ok    %s\n' "$*"; }

cleanup() {
  local rc=$?
  umount -R /mnt 2>/dev/null || true
  if (( rc != 0 && DESTRUCTIVE == 1 )); then
    cat <<'EOF'

  ==================================================================
   STOP - READ THIS BEFORE DOING ANYTHING ELSE
  ==================================================================

   The partition table was already converted to GPT, but the run did
   not finish. The disk cannot boot in legacy BIOS mode any more.

   NOTHING WAS DELETED. Every file is still there.

   Do NOT reinstall Arch. Do NOT format anything. Just run this same
   script again from this live session:

       bash /usb/MIGRATION/RUN-ME.sh

   It is safe to rerun. It detects the disk is already GPT and skips
   straight to installing the bootloader.

  ==================================================================
EOF
  fi
}
trap cleanup EXIT

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

echo "=============================================="
echo " Phase B - BIOS -> UEFI conversion"
echo "=============================================="
echo

# ============================================================ 1. environment
echo "==> [1/7] environment checks"

[[ $EUID -eq 0 ]] || fail "run as root"

# Positive test for the live session. Refusing only ext4 was too weak: this
# must never run against the system it is booted from.
if [[ ! -d /run/archiso ]]; then
  echo "  This does not look like the Arch live USB (/run/archiso is absent)."
  echo "  Converting the disk you are booted from cannot work."
  confirm "  Continue anyway?" || fail "aborted - nothing was changed"
fi
ok "live session"

[[ -d /sys/firmware/efi ]] || fail \
"this live session booted in LEGACY/BIOS mode, not UEFI.

  Reboot and pick the entry that starts with  UEFI:  for the Ventoy
  stick, otherwise grub-install cannot register a UEFI boot entry.

  If no UEFI: entry appears, Secure Boot or CSM is interfering -
  enter the BIOS and set Secure Boot to Disabled and CSM to Disabled."
ok "UEFI mode"

for t in sgdisk blkid lsblk partprobe arch-chroot findmnt udevadm; do
  command -v "$t" >/dev/null || fail "missing tool in the live session: $t"
done
ok "required tools present"
echo

# ============================================================ 2. identify
echo "==> [2/7] finding your disk by filesystem UUID"
udevadm settle 2>/dev/null || true

rootpart=$(blkid -U "$ROOT_UUID" 2>/dev/null || true)
bootpart=$(blkid -U "$BOOT_UUID" 2>/dev/null || true)

if [[ -z $rootpart || -z $bootpart ]]; then
  echo
  echo "  Disks this machine can see:"
  lsblk -o NAME,SIZE,FSTYPE,LABEL,SERIAL | sed 's/^/    /'
  echo
  [[ -n $rootpart ]] || echo "  NOT FOUND: root filesystem $ROOT_UUID"
  [[ -n $bootpart ]] || echo "  NOT FOUND: boot filesystem $BOOT_UUID"
  fail "this is not the right disk, or the disk is not detected.

  The Arch SSD is a WD Blue SN580 500GB, serial 2404EE402177.

  If it is not in the list above:
    - power off, and check the M.2 screw is holding the drive down
    - move it to the M.2 slot closest to the CPU socket (M.2_1)
    - check the BIOS storage page lists the drive at all

  Nothing has been changed. It is safe to power off now."
fi

disk=/dev/$(lsblk -no PKNAME "$rootpart" | head -1)
[[ -b $disk ]] || fail "could not resolve the parent disk of $rootpart"

bootdisk=/dev/$(lsblk -no PKNAME "$bootpart" | head -1)
[[ $bootdisk == "$disk" ]] || fail \
"root and boot are on different disks ($disk vs $bootdisk). Aborting."

echo "    root partition : $rootpart"
echo "    boot partition : $bootpart"
echo "    target disk    : $disk  ($(lsblk -dno SIZE "$disk" | tr -d ' '), serial $(lsblk -dno SERIAL "$disk" | tr -d ' '))"
ok "root and boot are on the same disk"
echo

# ============================================================ 3. pre-flight
# Everything here happens BEFORE the partition table is touched, so any
# failure leaves a disk that still boots exactly as it did.
echo "==> [3/7] pre-flight - verifying this really is the system to convert"
echo "    (read-only; nothing is written in this step)"

mkdir -p /mnt
umount -R /mnt 2>/dev/null || true

# An ext4 filesystem with an unreplayed journal - the normal state after an
# unclean shutdown - refuses a plain read-only mount with "recovery required on
# readonly filesystem". noload skips the replay, which is fine for looking at
# files; the read-write mount later on replays it properly.
if ! mount -o ro "$rootpart" /mnt 2>/dev/null; then
  if mount -o ro,noload "$rootpart" /mnt 2>/dev/null; then
    echo "    NOTE: the filesystem has an unreplayed journal (the old machine"
    echo "          was not shut down cleanly). Inspecting without it; it gets"
    echo "          replayed normally when the disk is mounted for writing."
  else
    fail "cannot mount $rootpart even read-only.

  The filesystem may be damaged. Check it before converting anything:
      fsck.ext4 -n $rootpart
  Nothing has been changed."
  fi
fi
mount -o ro "$bootpart" /mnt/boot || fail "cannot mount $bootpart read-only"

[[ -f /mnt/etc/fstab ]] || fail "no /etc/fstab on this disk - it is not an Arch install"
[[ -d /mnt/home/thiencn ]] || fail "no /home/thiencn on this disk - wrong disk"
EXPECT_HOSTNAME=$(cat /mnt/etc/hostname 2>/dev/null || echo "?")
ok "Arch install found (hostname: $EXPECT_HOSTNAME)"

# A GPT conversion changes every PARTUUID. If anything mounts by PARTUUID the
# machine would not come up, and there would be no obvious reason why.
if grep -q 'PARTUUID' /mnt/etc/fstab; then
  fail "/etc/fstab mounts something by PARTUUID.

  MBR -> GPT changes every PARTUUID, so those mounts would break.
  Convert them to UUID= first. Nothing has been changed."
fi
ok "fstab uses filesystem UUIDs only (survives the conversion)"

grep -q "$ROOT_UUID" /mnt/etc/fstab || fail "fstab does not reference $ROOT_UUID - wrong disk"
ok "fstab matches this root filesystem"

# Phase A removed 'autodetect' so the initramfs carries drivers for hardware
# that was not present when it was built. Without that, the new board's NVMe
# controller may have no driver and the machine cannot find its own root.
if grep -qE '^HOOKS=.*[( ]autodetect[ )]' /mnt/etc/mkinitcpio.conf; then
  fail "this disk still has 'autodetect' in mkinitcpio HOOKS.

  Phase A (04-prep-for-new-pc.sh) was never run on it, so the initramfs
  only contains drivers for the OLD machine. Converting now would give
  you a disk that boots to 'unable to find root device'.

  Put the disk back in the old PC, run Phase A, reboot, then come back.
  Nothing has been changed."
fi
ok "initramfs was built without autodetect (Phase A ran)"

# grub-install must be able to build an EFI image entirely offline.
[[ -d /mnt/usr/lib/grub/x86_64-efi ]] || fail \
"the installed grub has no x86_64-efi modules (/usr/lib/grub/x86_64-efi).
  A UEFI bootloader cannot be built offline. Nothing has been changed."
[[ -x /mnt/usr/bin/grub-install ]] || fail "grub-install missing on the target system"
[[ -x /mnt/usr/bin/efibootmgr ]] || fail "efibootmgr missing on the target system (Phase A installs it)"
ok "offline UEFI grub-install is possible ($(ls /mnt/usr/lib/grub/x86_64-efi | wc -l) modules)"

# A kernel and a plausibly-sized initramfs must exist, or there is nothing
# to boot no matter how well the bootloader installs.
[[ -f /mnt/boot/vmlinuz-linux ]] || fail "/boot/vmlinuz-linux is missing"
for img in /mnt/boot/initramfs-linux.img /mnt/boot/initramfs-linux-lts.img; do
  [[ -f $img ]] || fail "$img is missing"
  sz=$(stat -c%s "$img")
  (( sz > 50000000 )) || fail "$img is only $((sz/1024/1024))MB - truncated. Rebuild it in the old PC first."
done
ok "kernel and both initramfs present and full size"

[[ -f /mnt/boot/amd-ucode.img ]] || fail "/boot/amd-ucode.img missing - Phase A did not complete"
ok "amd-ucode present for the new CPU"

esp_free=$(df --output=avail -m /mnt/boot | tail -1 | tr -d ' ')
(( esp_free >= MIN_ESP_FREE_MB )) || fail \
"/boot has only ${esp_free}MB free; grub-install needs about ${MIN_ESP_FREE_MB}MB."
ok "/boot has ${esp_free}MB free"

esp_fs=$(lsblk -no FSTYPE "$bootpart")
[[ $esp_fs == vfat ]] || fail "/boot is $esp_fs, but an EFI System Partition must be FAT. Aborting."
ok "/boot is $esp_fs (valid ESP filesystem)"

umount -R /mnt
ok "unmounted cleanly"

# GPT keeps a backup header + partition table in the LAST 33 sectors of the
# disk. If a partition runs into them, converting would corrupt its tail.
diskname=$(basename "$disk")
tot=$(cat "/sys/class/block/$diskname/size")
last_end=0
for pdir in "/sys/class/block/$diskname/$diskname"*/; do
  [[ -f "$pdir/start" ]] || continue
  s=$(cat "$pdir/start"); n=$(cat "$pdir/size"); e=$(( s + n - 1 ))
  if (( e > last_end )); then last_end=$e; fi
done
tail_free=$(( tot - 1 - last_end ))
if (( tail_free < GPT_TAIL_SECTORS )); then
  fail "only ${tail_free} free sectors at the end of the disk; GPT needs ${GPT_TAIL_SECTORS}.
  Converting would overwrite the end of the last partition. Aborting."
fi
ok "${tail_free} free sectors at end of disk (GPT needs ${GPT_TAIL_SECTORS})"

# Rewriting the partition table under a mounted filesystem risks the kernel
# never re-reading it. The pre-flight umount above is checked by set -e, but
# something could be mounted from outside /mnt - a previous partial run, or an
# automount. Verify directly rather than assume.
# NOTE: findmnt takes ONE -S; a second silently replaces the first, so each
# partition must be asked about separately.
mounts_of() {
  local out=""
  for p in "$rootpart" "$bootpart"; do
    out+=$(findmnt -rno TARGET -S "$p" 2>/dev/null || true)
    out+=" "
  done
  echo "${out// /}"
}
if [[ -n $(mounts_of) ]]; then
  echo "    something on $disk is mounted - unmounting"
  umount "$rootpart" 2>/dev/null || true
  umount "$bootpart" 2>/dev/null || true
  [[ -z $(mounts_of) ]] || fail "$rootpart or $bootpart is still mounted.
  Unmount it and run this again. Nothing has been changed."
fi
ok "nothing on $disk is mounted"
echo

# ============================================================ 4. confirm
echo "==> [4/7] confirm"
echo
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT,SERIAL | sed 's/^/    /'
echo
echo "    ONLY $disk will be modified."
echo "    Any Windows disk is not touched - it is not even opened."
echo
echo "    After this point the disk boots UEFI only, and the old PC can no"
echo "    longer boot it. Your files are not affected either way."
echo
confirm "    Proceed?" || fail "aborted by user - nothing was changed"
echo

# ============================================================ 5. convert
echo "==> [5/7] partition table"

current_pt=$(lsblk -dno PTTYPE "$disk")
echo "    current: $current_pt"

if [[ $current_pt == gpt ]]; then
  echo "    already GPT - skipping conversion (safe rerun)"
  DESTRUCTIVE=1
else
  DESTRUCTIVE=1
  sgdisk -g "$disk" || fail "sgdisk conversion failed"
  partprobe "$disk" 2>/dev/null || true
  udevadm settle 2>/dev/null || true
  new_pt=$(lsblk -dno PTTYPE "$disk")
  [[ $new_pt == gpt ]] || fail "conversion did not take (still $new_pt)"
  ok "converted to GPT"
fi

# lsblk reports 'gpt' off the protective MBR alone, so verify the real thing.
# This is deliberately NOT fatal. The table is already rewritten by now, so
# stopping here would guarantee a disk with a GPT and no bootloader - strictly
# worse than carrying on. A genuinely broken table makes grub-install fail a
# few lines below with a clearer error anyway. And a fatal check that trips on
# a benign warning would trip again on every rerun, with no way past it.
verify_out=$(sgdisk -v "$disk" 2>&1 || true)
if grep -q 'No problems found' <<<"$verify_out"; then
  ok "GPT structures verified"
else
  echo
  echo "    WARNING: sgdisk -v did not report a clean table:"
  sed 's/^/      /' <<<"$verify_out"
  echo "    Continuing anyway - installing a bootloader is the priority."
  echo "    If the next step fails, that is the real answer."
  echo
fi

# Filesystem UUIDs live inside the filesystems and must be unaffected.
udevadm settle 2>/dev/null || true
[[ $(blkid -U "$ROOT_UUID" 2>/dev/null || true) == "$rootpart" ]] || fail \
"root filesystem UUID no longer resolves after conversion. Do not reboot."
[[ $(blkid -U "$BOOT_UUID" 2>/dev/null || true) == "$bootpart" ]] || fail \
"boot filesystem UUID no longer resolves after conversion. Do not reboot."
ok "both filesystem UUIDs still resolve"

# Mark /boot as an EFI System Partition. Read the partition number from sysfs;
# ${bootpart##*p} works for /dev/nvme0n1p1 but returns the whole path for
# /dev/sda1, which would feed sgdisk a nonsense argument.
partnum=$(cat "/sys/class/block/$(basename "$bootpart")/partition" 2>/dev/null || true)
[[ $partnum =~ ^[0-9]+$ ]] || fail "could not determine the partition number of $bootpart"
sgdisk -t "${partnum}:EF00" "$disk" >/dev/null || fail "could not set the ESP type flag"
partprobe "$disk" 2>/dev/null || true
udevadm settle 2>/dev/null || true
ok "partition $partnum marked EF00 (EFI System Partition)"
echo
sgdisk -p "$disk" | sed 's/^/    /'
echo

# ============================================================ 6. bootloader
echo "==> [6/7] installing the UEFI bootloader (the step that matters)"

mount "$rootpart" /mnt || fail "cannot mount root after conversion"
mount "$bootpart" /mnt/boot || fail "cannot mount /boot after conversion"

# Order is deliberate. --removable writes \EFI\BOOT\BOOTX64.EFI, the path every
# UEFI board checks when no NVRAM entry matches. It never calls efibootmgr, so
# it cannot fail because NVRAM is full - and on its own it produces a disk that
# boots anywhere. The NVRAM entry is the nice-to-have, so it goes second and is
# allowed to fail. The previous version had these the other way round, which
# made the fallback unreachable in exactly the case it existed for.
arch-chroot /mnt /bin/bash <<'CHROOT' || fail "the UEFI bootloader could not be installed. Do not reboot; rerun this script."
set -uo pipefail
rc=0

echo "    [a] firmware fallback copy (needs no NVRAM)"
if grub-install --target=x86_64-efi --efi-directory=/boot --removable --recheck; then
  echo "        installed"
else
  echo "        FAILED"; rc=1
fi

if [[ -f /boot/EFI/BOOT/BOOTX64.EFI ]]; then
  echo "        verified /boot/EFI/BOOT/BOOTX64.EFI"
else
  echo "        MISSING /boot/EFI/BOOT/BOOTX64.EFI"; rc=1
fi

echo "    [b] named NVRAM entry 'Arch' (optional - the disk boots without it)"
if grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Arch --recheck; then
  echo "        registered"
else
  echo "        WARNING: could not register an NVRAM entry."
  echo "        This is not fatal. Boot with the firmware boot menu and pick"
  echo "        the entry called 'UEFI OS' or the drive model name."
fi

echo "    EFI directory now contains:"
ls -R /boot/EFI/ 2>/dev/null | sed 's/^/      /' || true
exit $rc
CHROOT
ok "bootloader installed"

echo
echo "    UEFI boot entries the firmware now knows about:"
efibootmgr -v 2>/dev/null | sed 's/^/      /' || echo "      (efibootmgr unavailable in the live session)"
echo

# ============================================================ 7. tidy up
# Everything from here is convenience, not correctness. The machine already
# boots. Nothing in this section is allowed to abort the script.
echo "==> [7/7] configuration tidy-up (non-critical)"

arch-chroot /mnt /bin/bash <<'CHROOT' || echo "    (tidy-up reported problems - the machine still boots)"
set -uo pipefail

# Back up only if no backup exists yet, so a second run cannot overwrite the
# pristine original with an already-modified copy.
echo "  removing nvidia_drm.modeset=1 from the kernel command line"
[[ -e /etc/default/grub.bak ]] || cp -a /etc/default/grub /etc/default/grub.bak
sed -i 's/ *nvidia_drm\.modeset=1//' /etc/default/grub
grep '^GRUB_CMDLINE_LINUX_DEFAULT' /etc/default/grub | sed 's/^/    /'

# GBM_BACKEND=nvidia-drm and __GLX_VENDOR_LIBRARY_NAME=nvidia will stop
# Hyprland starting on an AMD card. The file itself must stay, because
# hyprland.conf 'source's it - so comment out the directives instead.
NV=/home/thiencn/.config/hypr/nvidia.conf
if [[ -f $NV ]]; then
  [[ -e "$NV.nvidia-backup" ]] || cp -a "$NV" "$NV.nvidia-backup"
  sed -i 's/^\([^#[:space:]]\)/# \1/' "$NV"
  chown thiencn:thiencn "$NV" "$NV.nvidia-backup" 2>/dev/null || true
  echo "    commented out; original kept at $NV.nvidia-backup"
else
  echo "    WARNING: $NV not found - check Hyprland's NVIDIA settings by hand"
fi

# The existing grub.cfg already works under UEFI: it preloads part_gpt and
# finds everything with 'search --fs-uuid'. Regenerating only drops the nvidia
# cmdline, so if it fails, keeping the old file is the right outcome.
echo "  regenerating grub.cfg"
cp -a /boot/grub/grub.cfg /boot/grub/grub.cfg.bios.bak 2>/dev/null || true
if grub-mkconfig -o /boot/grub/grub.cfg; then
  echo "    written"
else
  echo "    WARNING: grub-mkconfig failed."
  if [[ -f /boot/grub/grub.cfg.bios.bak ]]; then
    cp -a /boot/grub/grub.cfg.bios.bak /boot/grub/grub.cfg
    echo "    restored the previous grub.cfg - it boots fine under UEFI too"
  fi
fi
CHROOT

echo
echo "==> unmounting"
sync
umount -R /mnt || echo "    WARNING: /mnt would not unmount. Run 'sync', then power off from the menu."
DESTRUCTIVE=0   # finished successfully; the failure notice must not print

cat <<EOF

==============================================
 Phase B complete.
==============================================

Shut down, REMOVE THE USB STICK, then power on:

    poweroff

FIRST BOOT

  If it goes straight into Windows, that is NOT a failure. Press the
  boot menu key (F8 / F11 / F12) and pick whichever entry is NOT
  "Windows Boot Manager". Depending on the board it is called:

      Arch          or      UEFI OS      or      WD Blue SN580

  Then set that one first in the BIOS boot order.

  A black screen for the first 1-3 minutes on a brand new AM5 board is
  normal - the memory is being trained. Do not power off during it.

  Make sure the monitor cable is in the GRAPHICS CARD, not the
  motherboard.

AFTER YOU REACH THE DESKTOP

    lspci -k | grep -A3 VGA        # want: Kernel driver in use: amdgpu

  Then finish the job. The script is already on the disk, so the USB
  does not need to be plugged in:

    sudo bash ~/home-migration/06-post-boot-cleanup.sh

  That removes the NVIDIA packages, which is deliberately NOT done here.

Backups made on the disk:
    /etc/default/grub.bak
    /boot/grub/grub.cfg.bios.bak
    /home/thiencn/.config/hypr/nvidia.conf.nvidia-backup
EOF
