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
- Target: AMD Ryzen 7 7800X3D + Radeon RX 9070 XT + B650M

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

## Phase B — conversion, in the NEW PC

This is the point of no return: afterwards the old machine can no longer boot.
Only start once the new PC is assembled.

### 1. Move the disk

Power off, remove the SSD with serial `2404EE402177`, install it in the new PC.
Plug in the Ventoy USB stick.

### 2. Boot the live USB

Power on → boot menu key (**F8 / F11 / F12**) → select the USB stick.

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

```bash
mount /dev/disk/by-uuid/4776357f-67c6-4d1e-86aa-9ca39a1c6f85 /mnt
cp /mnt/home/thiencn/home-migration/05-uefi-convert.sh /root/
umount /mnt
bash /root/05-uefi-convert.sh
```

It needs no internet — the `x86_64-efi` GRUB modules ship with the already
installed `grub` package, and Phase A supplied `efibootmgr`.

The script verifies UEFI mode, finds the disk by UUID, checks that root and
boot are on the *same* disk, lists every disk present, and asks before
changing anything. **Only that one disk is touched — a Windows disk is safe.**

Order is deliberate: `grub-install` runs **before** anything NVIDIA is removed,
so a package problem cannot leave the machine unbootable.

### 4. Finish

Shut down, **remove the USB**, power on.

---

## Your data is never at risk

No filesystem is formatted and no files are moved. The conversion rewrites the
**partition table** — the small index at the start of the disk — and installs a
bootloader. Think of it as replacing the label on a filing cabinet: the folders
inside do not move.

Filesystem UUIDs live inside the filesystems, so they survive the MBR → GPT
change. `/etc/fstab` needs no edits.

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

## Files

| Path | Purpose |
|---|---|
| `~/home-migration/04-prep-for-new-pc.sh` | Phase A — safe prep |
| `~/home-migration/05-uefi-convert.sh` | Phase B — conversion |
| `~/home-migration/README-NEW-PC.txt` | Plain-text crib sheet |

All three travel with the disk, so they are available from the live session at
`/mnt/home/thiencn/home-migration/`.

**Photograph the commands in step 3 before starting** — you will be at a bare
text prompt with no browser.
