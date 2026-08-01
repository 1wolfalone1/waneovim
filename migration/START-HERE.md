# NEW PC — what to do

**Photograph this page before you start.** The live session has no browser.

| | |
|---|---|
| Your disk | serial `2404EE402177` (WD Blue SN580, 500GB) |
| Root filesystem | UUID `4776357f-67c6-4d1e-86aa-9ca39a1c6f85` |
| Boot / ESP | UUID `BA53-EA76` |

---

## Steps

**1. Move the disk**
Power off the old PC. Take out the SSD with serial `2404EE402177`. Put it in
the new PC's M.2 slot.

**2. Boot the stick**
Plug in this USB. Power on. Press the boot menu key — **F8 / F11 / F12**, the
screen tells you — and pick the USB.

> If two entries show for the stick, pick the one starting with **`UEFI:`**.
> This matters. The script refuses to run if you booted in legacy mode.

**3. Ventoy menu**
`archlinux-x86_64.iso` → *Boot in normal mode* →
**Arch Linux install medium (x86_64, UEFI)**

**4. Wait for the prompt**

```
root@archiso ~ #
```

There is no installer screen. A plain text prompt is correct.

**5. Type these three lines**

```bash
mkdir -p /usb
mount -L Ventoy /usb
bash /usb/MIGRATION/RUN-ME.sh
```

Answer the questions it asks. It shows you every disk and only touches the Arch
one. **A Windows disk is not touched.**

**6. Finish**
Shut down, **pull out the USB**, power on.

---

## If it boots into Windows

Not a failure. Press the boot menu key, pick the entry named **`Arch`**. Then
set it first in the BIOS boot order.

## If step 5 says `mount: unknown filesystem type 'exfat'`

Load the driver first, then repeat step 5:

```bash
modprobe exfat
```

Still failing? The same scripts are on the Arch disk itself:

```bash
mount /dev/disk/by-uuid/4776357f-67c6-4d1e-86aa-9ca39a1c6f85 /mnt
cp /mnt/home/thiencn/home-migration/05-uefi-convert.sh /root/
umount /mnt
bash /root/05-uefi-convert.sh
```

## If anything else goes wrong

**Nothing is deleted at any point.** Boot this stick again and you are back at a
root prompt with the disk intact.

Full notes and recovery commands:

```bash
less /usb/MIGRATION/GUIDE.md
```
