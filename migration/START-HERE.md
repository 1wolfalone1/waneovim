# NEW PC — what to do

**Photograph this page before you start.** The live session has no browser.

| | |
|---|---|
| Your disk | WD Blue SN580 500GB, serial `2404EE402177` |
| Root filesystem | UUID `4776357f-67c6-4d1e-86aa-9ca39a1c6f85` |
| Boot / ESP | UUID `BA53-EA76` |

---

## 0. Before you start — while you still have Windows and internet

If the Windows SSD uses **BitLocker, suspend it first.** Step 1 changes BIOS
settings, which makes Windows demand a 48-digit recovery key on its next boot.
In Windows, as administrator:

```
manage-bde -protectors -disable C:
```

Or save the key from `account.microsoft.com/devices/recoverykey`.

**This cannot be fixed afterwards from Linux.** Skip only if you are certain
BitLocker is off.

## 1. Hardware and BIOS

Power off the old PC. Take out the SSD with serial `2404EE402177`. Put it in
the new PC, in the **M.2 slot nearest the CPU** (usually M.2_1).

> **Monitor cable goes into the graphics card, not the motherboard.**
> The 7800X3D has built-in graphics, so the motherboard port gives you a
> perfectly normal BIOS — and then a black screen later.

> **First power-on of a new AM5 board takes 1–3 minutes of black screen**
> while it trains the memory. This is normal. Do not power off. Wait.

Press **DEL** to enter the BIOS and set:

| Setting | Value |
|---|---|
| Secure Boot | **Disabled** |
| CSM / Legacy Support | **Disabled** |
| Integrated Graphics | **Disabled** (or Auto) |

Secure Boot is the big one — leave it on and the USB may refuse to boot, or
worse, everything works until the very last reboot and then the machine only
starts Windows.

Save and exit.

## 2. Boot the USB

Plug in this USB. Power on, press the boot menu key — **F8 / F11 / F12**, the
screen tells you — and pick the USB.

> If two entries show for the stick, pick the one starting with **`UEFI:`**.

Ventoy menu → `archlinux-x86_64.iso` → *Boot in normal mode* →
**Arch Linux install medium (x86_64, UEFI)**

Wait for the prompt:

```
root@archiso ~ #
```

There is no installer screen. A plain text prompt is correct.

## 3. Run it

```bash
mkdir -p /usb
mount -L Ventoy /usb
bash /usb/MIGRATION/RUN-ME.sh
```

It checks everything before writing anything, and tells you if something is
wrong. **Only the Arch disk is touched — the Windows disk is never opened.**

Answer its questions. When it finishes:

```bash
poweroff
```

Then **pull out the USB** and power on.

## 4. First boot

If it goes straight into Windows, that is **not** a failure. Press the boot
menu key and pick whichever entry is **not** `Windows Boot Manager`. Depending
on the board it is called:

```
Arch        or        UEFI OS        or        WD Blue SN580
```

Then set that entry first in the BIOS boot order.

## 5. After you reach the desktop

```bash
lspci -k | grep -A3 VGA        # want: Kernel driver in use: amdgpu
```

Then finish up. This removes the NVIDIA driver — not needed to boot, which is
exactly why it is a separate step:

```bash
sudo bash ~/home-migration/06-post-boot-cleanup.sh
```

---

# When things go wrong

**`mount: unknown filesystem type 'exfat'`**
```bash
modprobe exfat      # then repeat step 3
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

**Script says the disk is not found** — power off. Reseat the SSD in the M.2
slot nearest the CPU and check the little screw holds it flat. Check the BIOS
storage page can see it at all.

**Script stopped after saying the disk is now GPT** — just run step 3 again.
It is safe to rerun and carries on from where it stopped.
**Do not reinstall. Do not format.**

**Anything else** — nothing is ever deleted. Boot this stick again and you are
back at a root prompt with the disk intact. Full notes:

```bash
less /usb/MIGRATION/GUIDE.md
```

**No Windows entry in the GRUB menu** — expected. Use the firmware boot menu
(F11) for Windows, or enable it later with `GRUB_DISABLE_OS_PROBER=false` in
`/etc/default/grub`.
