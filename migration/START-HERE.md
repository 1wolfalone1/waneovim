# NEW PC — what to do

**Photograph this page before you start.** The live session has no browser.

| The new machine | |
|---|---|
| CPU | AMD Ryzen 7 **9800X3D** |
| Board | **GIGABYTE X870M AORUS ELITE WIFI7** |
| GPU | Radeon **RX 9070 XT** 16GB |
| | order DH040844 |

| The disk to move | |
|---|---|
| Drive | WD Blue SN580 500GB, serial `2404EE402177` |
| Root filesystem | UUID `4776357f-67c6-4d1e-86aa-9ca39a1c6f85` |
| Boot / ESP | UUID `BA53-EA76` |

> The new PC comes with **its own 512GB NVMe** (Hiksemi Wave), so there will be
> two similar-looking drives inside. **Never go by size, and never by
> `nvme0`/`nvme1`** — those names change between machines. Go by the serial.
> The scripts do this for you and print what they found.

---

## 0. Before you start — while you still have Windows and internet

If you are fitting a Windows SSD and it uses **BitLocker, suspend it first.**
Step 3 changes BIOS settings, which makes Windows demand a 48-digit recovery
key on its next boot. In Windows, as administrator:

```
manage-bde -protectors -disable C:
```

Or save the key from `account.microsoft.com/devices/recoverykey`.

**This cannot be fixed afterwards from Linux.**

## 1. Hardware

Power off the old PC. Take out the SSD with serial `2404EE402177`. Fit it in
**any free M.2 slot** — the Hiksemi will already be in one of them, leave it
alone.

> **Monitor cable goes into the graphics card, not the motherboard.**
> The 9800X3D has built-in graphics, so the motherboard port gives you a
> perfectly normal BIOS — and then a black screen later.

## 2. First power-on — this part looks broken and is not

The first boot of a new board with new DDR5 takes **up to 5 minutes of black
screen** while it trains the memory. The machine may **restart itself two or
three times** during this. This is normal. Do not power off.

Gigabyte boards have four status LEDs: **CPU / DRAM / VGA / BOOT**. If DRAM is
still lit after 5 minutes, power off and reseat the RAM.

## 3. BIOS settings

Press **DEL** at power-on to enter the BIOS.

| Setting | Value |
|---|---|
| Secure Boot | **Disabled** |
| CSM / Legacy Support | **Disabled** (may not exist — that's fine) |
| Integrated Graphics | **Disabled** (or Auto) |

On Gigabyte, Secure Boot lives under the **Boot** section. If it will not
switch off, go into **Key Management**, clear or delete the Platform Key, then
set it to Disabled.

Secure Boot is the big one — leave it on and the USB may refuse to boot, or
worse, everything works until the very last reboot and then the machine only
ever starts Windows.

Save and exit.

## 4. Boot the USB

Plug in this USB. Power on and press **F12** for the boot menu — F12 is the
Gigabyte boot-menu key, DEL is the BIOS. Pick the USB.

> If two entries show for the stick, pick the one starting with **`UEFI:`**.

Ventoy menu → `archlinux-x86_64.iso` → *Boot in normal mode* →
**Arch Linux install medium (x86_64, UEFI)**

Wait for the prompt:

```
root@archiso ~ #
```

There is no installer screen. A plain text prompt is correct.

## 5. Run it

```bash
mkdir -p /usb
mount -L Ventoy /usb
bash /usb/MIGRATION/RUN-ME.sh
```

It checks everything before writing anything. It finds your disk by UUID and
prints the serial, so **the extra Hiksemi drive cannot be picked by mistake.**
Only the Arch disk is touched.

Answer its questions. When it finishes:

```bash
poweroff
```

Then **pull out the USB** and power on.

## 6. First boot into Arch

If it goes straight into Windows, that is **not** a failure. Press **F12** and
pick whichever entry is **not** `Windows Boot Manager`. Depending on the board
it is called:

```
Arch        or        UEFI OS        or        WD Blue SN580
```

Then set that entry first in the BIOS boot order.

## 7. After you reach the desktop

```bash
lspci -k | grep -A3 VGA        # want: Kernel driver in use: amdgpu
```

Then finish up. This removes the NVIDIA driver — not needed to boot, which is
exactly why it is a separate step:

```bash
sudo bash ~/home-migration/06-post-boot-cleanup.sh
```

> Your new MSI monitor is not in the old config, so Hyprland will fall back to
> its default mode — possibly 60Hz instead of 144Hz. Nothing is broken. Fix it
> later in `~/.config/hypr/monitors.conf`.

---

# When things go wrong

**`mount: unknown filesystem type 'exfat'`**
```bash
modprobe exfat      # then repeat step 5
```

**`mount: /usb: can't find LABEL=Ventoy`**
```bash
blkid                    # find the exfat line, note its device
mount /dev/sda1 /usb     # use that device name
bash /usb/MIGRATION/RUN-ME.sh
```

**USB will not mount at all** — the scripts are on the Arch disk too:
```bash
mount /dev/disk/by-uuid/4776357f-67c6-4d1e-86aa-9ca39a1c6f85 /mnt
cp /mnt/home/thiencn/home-migration/05-uefi-convert.sh /root/
umount /mnt
bash /root/05-uefi-convert.sh
```

**Script says the disk is not found** — it prints every drive it can see. Look
for serial `2404EE402177`. If it is missing: power off, reseat the drive, check
the little screw holds it flat, try a different M.2 slot, and check the BIOS
storage page can see it at all.

**Script stopped after saying the disk is now GPT** — just run step 5 again.
It is safe to rerun and carries on from where it stopped.
**Do not reinstall. Do not format.**

**Anything else** — nothing is ever deleted. Boot this stick again and you are
back at a root prompt with the disk intact. Full notes:

```bash
less /usb/MIGRATION/GUIDE.md
```

**No Windows entry in the GRUB menu** — expected. Use **F12** for Windows, or
enable it later with `GRUB_DISABLE_OS_PROBER=false` in `/etc/default/grub`.
