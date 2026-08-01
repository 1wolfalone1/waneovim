# Migrating this Arch install to the new AMD PC

Moving the existing Arch system disk from the old X99 machine into the new
AM5 build, without reinstalling. Everything is kept — files, configs, this
Neovim setup, HyDE, VMs.

The install currently boots **legacy BIOS**. The new board is **UEFI only**.
That conversion is the core of this document.

---

## Identity — memorise these, not device names

NVMe device names (`nvme0n1`, `nvme1n1`) **change between machines**. They
already changed once on the old PC, which is why its `/etc/fstab` comments
were wrong. Always match on UUID or serial.

| What | Value |
|---|---|
| System SSD serial | `2404EE402177` (WD Blue SN580 500GB) |
| Root filesystem UUID | `4776357f-67c6-4d1e-86aa-9ca39a1c6f85` |
| Boot / ESP UUID | `BA53-EA76` |

The second SSD (`2329BF403915`) held the old `/home` and is not part of this
migration.

## Starting state

- `/` and `/home` on one partition, `/boot` (1 GB FAT32) on the same disk
- Legacy BIOS boot, MBR partition table, GRUB `i386-pc` in the MBR gap
- NVIDIA RTX 3060, Intel CPU
- Target: AMD Ryzen 7 **9800X3D** (Zen 5) + Radeon RX 9070 XT +
  **GIGABYTE X870M AORUS ELITE WIFI7** (order DH040844)
- The new machine ships with its own 512GB NVMe (Hiksemi Wave), so two
  similar drives will be present. Identification is by filesystem UUID and
  serial throughout — never by size or by `nvme0`/`nvme1`.

## What has to change

| Item | Now | Needed |
|---|---|---|
| Firmware boot | Legacy BIOS | UEFI |
| Partition table | MBR (`dos`) | GPT |
| `/boot` | plain FAT32 | ESP (type `EF00`) |
| GRUB target | `i386-pc` | `x86_64-efi` |
| GPU driver | `nvidia-open-dkms` | `amdgpu` + `vulkan-radeon` |
| Microcode | `intel-ucode` | `amd-ucode` |
| initramfs | built with `autodetect` | built without it |

Everything else is portable: fstab uses filesystem UUIDs, `grub.cfg` locates
root with `search --fs-uuid`, and `mkinitcpio.conf` has `MODULES=()`. No
hardcoded disk numbers anywhere.

---

## Phase A — safe prep, on the OLD PC

### Prerequisite: the system must be up to date

Phase A installs packages, so the pacman sync database has to be current.
A stale database still lists versions the mirrors have deleted, and every
download fails with **404** — which looks like a mirror outage but is not.

```bash
sudo pacman -Sy archlinux-keyring
sudo pacman -Syu
```

Reboot after that if the kernel was updated.

The keyring goes first, or signature checks on newer packages fail. Never run
`pacman -Sy` and then install packages on its own — that is a partial upgrade
and a known way to break Arch.

`04-prep-for-new-pc.sh` checks the database age and refuses to run if it is
more than 14 days old, rather than letting pacman emit a wall of 404s.

> Watch two things during a long-overdue upgrade on this machine:
> `nvidia-open-dkms` has to rebuild against the new kernel (a DKMS failure
> means a black screen on next boot — keep the live USB nearby), and the
> `chaotic-aur` repo can lag behind core/extra and cause conflicts.

### Running it

Run while the old machine still works. **Nothing breaks.** It only adds what
the new hardware needs.

```bash
sudo bash ~/home-migration/04-prep-for-new-pc.sh
```

It installs `amd-ucode`, `vulkan-radeon`, `lib32-vulkan-radeon`, `efibootmgr`
and `gptfdisk`; strips `autodetect` from `mkinitcpio` HOOKS so the initramfs
carries drivers for any hardware; then rebuilds initramfs and `grub.cfg`.
Backups go to `/var/backup-prep-<timestamp>/`, and a failed rebuild is rolled
back automatically.

**Then reboot and confirm the old PC still starts.** Do not skip this.

> Nothing NVIDIA is removed here. `nvidia-utils` currently satisfies
> `opengl-driver` and `vulkan-driver` for Hyprland — removing it before the AMD
> replacements exist takes the compositor with it.

## Verified against the final hardware

The build changed after this toolkit was written (7800X3D/B650M → 9800X3D/X870M).
Everything below was re-checked against the installed system rather than assumed:

| Concern | Result |
|---|---|
| Zen 5 microcode | `microcode_amd_fam1ah.bin` present in `amd-ucode` 20260622 |
| CPU vendor guard in `RUN-ME.sh` | 9800X3D is still `AuthenticAMD` — guard stays correct |
| RDNA4 GPU (unchanged) | `gc_12_0_*` / `dcn_4_0_1` firmware inside both initramfs |
| Kernels | 7.1.5 and 6.18.40-lts, both far past Zen 5 and RDNA4 support |
| X870M WiFi 7 | `mt7925e` module + `WIFI_RAM_CODE_MT7925` firmware present |
| X870M 2.5GbE | `r8169` present (also `igc`, `atlantic` as fallbacks) |
| X870 mandatory USB4 | `thunderbolt` module present; not boot-critical |
| Second NVMe in the machine | No script references a device name or size — identification is `blkid -U` plus serial, so a bundled Hiksemi drive is invisible to it |
| New MSI FHD monitor | Old `monitor=desc:` rules simply will not match; `hyprland.conf` has a catch-all `monitor = ,preferred,auto,auto`, so no black screen. May come up at 60Hz — cosmetic |

Nothing in the scripts needed changing for the new hardware. Only the
instruction cards did: boot-menu key, BIOS vendor, memory-training time, and
the presence of a second drive.

## Phase B — conversion, in the NEW PC

This is the point of no return: afterwards the old machine can no longer boot.
Only start once the new PC is assembled.

Phase B does **only** what is required to make the disk boot on the new board.
It deliberately does not remove NVIDIA packages and does not rebuild the
initramfs — see [Phase C](#phase-c--cleanup-once-the-new-pc-is-up) for why.

### 0. Before you start

If the Windows SSD uses **BitLocker, suspend it first** — the BIOS changes in
step 1 alter the TPM measurements and Windows will demand a 48-digit recovery
key on its next boot. From Windows, as administrator:

```
manage-bde -protectors -disable C:
```

This is the one item on the list that cannot be fixed afterwards from Linux.

### 1. Move the disk, then set up the BIOS

Power off, remove the SSD with serial `2404EE402177`, install it in **any free
M.2 slot** in the new PC — the bundled Hiksemi 512GB drive already occupies one
of them. Plug in the Ventoy USB stick.

Press **DEL** for the BIOS; **F12** is the boot menu on this Gigabyte board.

| BIOS setting | Value | Why |
|---|---|---|
| Secure Boot | **Disabled** | GRUB is unsigned. Left on, the USB may refuse to boot — or everything works until the final reboot and then only Windows starts. On Gigabyte it is under **Boot**; if it will not switch off, clear the Platform Key under **Key Management** first |
| CSM / Legacy | **Disabled** | Forces the UEFI path the conversion targets |
| Integrated Graphics | **Disabled** (or Auto) | The 9800X3D iGPU plus the dGPU gives Hyprland two cards and it can pick the one with no monitor attached |

Two things that look like failures and are not:

- **First power-on is up to 5 minutes of black screen** while DDR5 memory
  training runs, and the board may restart itself two or three times doing it.
  Do not power off. Gigabyte's DRAM status LED staying lit past that means
  reseat the RAM.
- **The monitor must be plugged into the graphics card, not the motherboard.**
  The iGPU will happily show you a normal BIOS and then nothing afterwards.

### 2. Boot the live USB

Power on → **F12** for the boot menu → select the USB stick.

> If two entries appear for the stick, pick the one prefixed **`UEFI:`**.
> The script aborts if the live session booted in legacy mode, because
> `grub-install` cannot register a UEFI boot entry from there.

Ventoy menu → `archlinux-x86_64.iso` → *Boot in normal mode* →
**Arch Linux install medium (x86_64, UEFI)**.

Wait for the prompt:

```
root@archiso ~ #
```

There is no installer UI. This is a plain root shell — that is expected.

### 3. Run the conversion

The whole toolkit is on the Ventoy stick's data partition, so it is reachable
without mounting the Arch disk first:

```bash
mkdir -p /usb
mount -L Ventoy /usb
bash /usb/MIGRATION/RUN-ME.sh
```

If exfat will not mount, `modprobe exfat` first. If the label is not found, run
`blkid` and mount the exfat device by name. Failing both, the same scripts are
on the Arch disk itself:

```bash
mount /dev/disk/by-uuid/4776357f-67c6-4d1e-86aa-9ca39a1c6f85 /mnt
cp /mnt/home/thiencn/home-migration/05-uefi-convert.sh /root/
umount /mnt
bash /root/05-uefi-convert.sh
```

It needs no internet — the `x86_64-efi` GRUB modules ship with the already
installed `grub` package, and Phase A supplied `efibootmgr`.

### What the checks actually protect against

`RUN-ME.sh` refuses to hand over unless all of these hold:

| Check | Failure it prevents |
|---|---|
| `/run/archiso` exists | Running against the installed system — you cannot convert the disk you booted from |
| `/sys/firmware/efi` exists | Legacy-mode live session, where `grub-install` cannot register a UEFI entry |
| CPU vendor is `AuthenticAMD` | Running Phase B in the *old* Intel machine and destroying a working boot |
| Both filesystem UUIDs resolve | A blank, wrong, or undetected SSD. Prints every disk it can see and what to do about it |
| Disk serial matches | A cloned or swapped drive (advisory — the UUID test is stronger) |

`05-uefi-convert.sh` then re-checks all of that and adds a **read-only
pre-flight** — it mounts the disk, verifies, and unmounts, all *before* the
partition table is touched:

| Pre-flight check | Why it must pass first |
|---|---|
| `/etc/fstab` and `/home/thiencn` exist | Proves this disk holds *this* system |
| `fstab` has no `PARTUUID` | MBR → GPT changes every PARTUUID; those mounts would silently break |
| `fstab` references the expected root UUID | Wrong disk |
| `mkinitcpio` HOOKS has no `autodetect` | Proves Phase A ran. Without it the initramfs has no driver for the new board's NVMe controller and the machine cannot find its own root |
| `/usr/lib/grub/x86_64-efi` exists | A UEFI bootloader can actually be built offline |
| `grub-install` and `efibootmgr` present | Same |
| Kernel + both initramfs exist and are > 50 MB | There is something to boot, and it is not truncated |
| `/boot/amd-ucode.img` exists | Microcode for the new CPU |
| `/boot` is FAT and has ≥ 32 MB free | Valid ESP with room for GRUB |
| ≥ 33 free sectors after the last partition | GPT keeps a backup header there; without room the conversion would corrupt the tail of the last partition |

Only after every one of those passes does it rewrite the partition table.
**Only that one disk is touched — a Windows disk is never even opened.**

### Order of operations, and why

```
sgdisk -g              MBR -> GPT
sgdisk -t N:EF00       mark /boot as an EFI System Partition
grub-install --removable    <-- MANDATORY, writes \EFI\BOOT\BOOTX64.EFI
grub-install --bootloader-id=Arch   <-- optional, writes an NVRAM entry
  ...only then, and never fatally: cmdline edit, nvidia.conf, grub-mkconfig
```

The `--removable` install goes **first and is mandatory**; the named NVRAM
entry goes second and is allowed to fail. This ordering matters: `--removable`
never calls `efibootmgr`, so it cannot fail because NVRAM is full, and on its
own it produces a disk that boots on any UEFI board. The earlier version ran
the NVRAM install first under `set -e`, which meant that on a board with full
NVRAM the script aborted *before* writing the fallback — the exact case the
fallback existed for.

### Rerunning is safe

If the script stops after the conversion, run it again. It detects the disk is
already GPT, skips that step, and continues to the bootloader. Backups are only
created when one does not already exist, so a second run cannot overwrite a
pristine original with an already-modified copy. An `EXIT` trap unmounts `/mnt`
and, if the table was already rewritten, prints exactly what to do next.

### 4. Finish

```bash
poweroff
```

Remove the USB, power on.

If it boots into Windows, that is not a failure. Press the boot menu key and
pick whichever entry is **not** `Windows Boot Manager`. Depending on the board
it will be called `Arch`, `UEFI OS`, or the drive model name — `--removable`
deliberately writes no NVRAM entry, so `UEFI OS` is a perfectly normal result.

## Phase C — cleanup, once the new PC is up

```bash
sudo bash ~/home-migration/06-post-boot-cleanup.sh
```

Removes the NVIDIA stack, rebuilds the initramfs, regenerates `grub.cfg`.

**None of this is needed to boot**, which is precisely why it is not in Phase B.
`mesa` provides `opengl-driver` and `vulkan-radeon` provides `vulkan-driver`, so
the AMD stack is already fully satisfied with the NVIDIA packages installed —
they simply never load without the card. Doing it offline from a live USB, with
no way to reinstall a package and no working desktop to fall back to, was pure
risk for zero boot-time benefit.

It also fixes a removal list that could never have worked:

```
pacman -Rns ... linux-firmware-nvidia
error: removing linux-firmware-nvidia breaks dependency
       'linux-firmware-nvidia' required by linux-firmware
```

`linux-firmware` is a metapackage that hard-depends on every
`linux-firmware-*` split package, so including it made pacman reject the whole
transaction and nothing at all was removed. The working list is
`nvidia-open-dkms nvidia-utils lib32-nvidia-utils libva-nvidia-driver` —
`libva-nvidia-driver` must be present or it blocks the removal of
`nvidia-utils`.

Phase C refuses to run unless `amdgpu` is already the driver in use, and unless
`mesa` and `vulkan-radeon` are installed. It backs the initramfs up to `/root`
(not `/boot` — a 1 GB ESP cannot hold a second copy of two 200 MB images) and
restores them if the rebuild produces anything under 50 MB.

---

## Your data is never at risk

No filesystem is formatted and no files are moved. The conversion rewrites the
**partition table** — the small index at the start of the disk — and installs a
bootloader. Think of it as replacing the label on a filing cabinet: the folders
inside do not move.

Filesystem UUIDs live inside the filesystems, so they survive the MBR → GPT
change. `/etc/fstab` needs no edits.

### The second SSD is a free backup — leave it alone

`01-copy-and-fstab.sh` *copied* `/home` to the system disk. It never erased the
original. The second SSD (serial `2329BF403915`, UUID
`34624526-36a5-4729-b266-350b5483acc1`) therefore still holds a complete 54 GB
copy of `/home`, and its fstab entry is commented out rather than deleted.

Do not wipe it or move it to another machine until the new PC is booting and
verified. It costs nothing to keep and it is the only copy that is not on the
disk being converted.

## If it does not boot

**Goes straight to Windows** — not a failure. Press the boot menu key and pick
the entry named `Arch`, then set it first in the BIOS boot order.

**Anything else** — boot the Ventoy stick again. You are back at a root prompt
with full access to an untouched disk. Mount and inspect:

```bash
mount /dev/disk/by-uuid/4776357f-67c6-4d1e-86aa-9ca39a1c6f85 /mnt
mount /dev/disk/by-uuid/BA53-EA76 /mnt/boot
arch-chroot /mnt
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Arch
grub-mkconfig -o /boot/grub/grub.cfg
```

## After reaching the desktop

```bash
lspci -k | grep -A3 VGA      # want: Kernel driver in use: amdgpu
glxinfo | grep -i renderer   # want: AMD / RADV
```

If Hyprland misbehaves, the old NVIDIA settings are preserved at
`~/.config/hypr/nvidia.conf.nvidia-backup`. The live file has every directive
commented out — the file itself must stay, because HyDE's config `source`s it.

## Files in this folder

| File | Purpose | Status |
|---|---|---|
| `README.md` | This guide | — |
| `START-HERE.md` / `START-HERE.txt` | One page to photograph before starting. Also at the USB root | — |
| `RUN-ME.sh` | **Entry point in the new PC.** Guards, then hands to `05` | to run |
| `01-copy-and-fstab.sh` | Copied `/home` onto the root disk, disabled its fstab mount | **done** |
| `02-post-reboot-verify.sh` | Delta-synced anything that changed during that copy | **done** |
| `03-check-boot-disk.sh` | Read-only: reports which disk holds the GRUB boot code | reusable |
| `04-prep-for-new-pc.sh` | **Phase A** — safe prep on the old PC | **done** |
| `05-uefi-convert.sh` | **Phase B** — BIOS→UEFI conversion from the live USB | to run |
| `06-post-boot-cleanup.sh` | **Phase C** — NVIDIA removal, on the new PC, after it boots | to run |

Scripts `01` and `02` are kept for the record — they consolidated `/home` off
the second SSD onto the system disk, which is why this migration only has to
move one drive. They are not part of the new-PC steps.

### Where the scripts live

Three copies, in order of convenience from the live session:

| Location | Reachable when |
|---|---|
| `/usb/MIGRATION/` on the Ventoy stick | always — no disk mount needed |
| `~/home-migration/` on the system disk | after mounting root at `/mnt` |
| this repo | only if the live session has network |

```bash
# from the USB (preferred)
mkdir -p /usb && mount -L Ventoy /usb && bash /usb/MIGRATION/RUN-ME.sh

# from the disk
mount /dev/disk/by-uuid/4776357f-67c6-4d1e-86aa-9ca39a1c6f85 /mnt
ls /mnt/home/thiencn/home-migration/

# from this repo
git clone https://github.com/1wolfalone1/waneovim.git /tmp/w
bash /tmp/w/migration/05-uefi-convert.sh
```

### Before you start

**Photograph `START-HERE.md`** (or the `.txt`, same content) — you will be at a bare
text prompt with no browser and no way to read any of this until something is
mounted. It is the single source of truth for the steps; there is deliberately
no second card that could disagree with it.

Every script here shares the same safety design: check assumptions before
acting, ask before anything destructive, back up what is modified, restore
automatically on failure. `03` is read-only. `04` leaves the machine
bootable. Only `05` is irreversible, and only after it prints what it will do
and you answer `y`.
