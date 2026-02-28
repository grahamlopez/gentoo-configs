# Building a Minimal Custom Initramfs for LUKS-Encrypted Root on Gentoo

## Overview

An initramfs is a compressed cpio archive containing a minimal root filesystem that the kernel extracts into a tmpfs (`rootfs`) very early in the boot process. The kernel then looks for an executable at `/init` within this filesystem and runs it as PID 1. This `/init` script is responsible for everything needed to prepare and mount the real root filesystem — including decrypting a LUKS volume — before handing off control to the real system's init (e.g., OpenRC or systemd).[^1][^2]

For a LUKS-encrypted root, the initramfs must prompt for a passphrase, use `cryptsetup` to unlock the partition, mount the decrypted device, and then `switch_root` into it. Building this by hand requires only a handful of static binaries, some device nodes, and a short shell script.[^3]

***

## How the Boot Process Works

Understanding the full chain from firmware to running system is essential before building a custom initramfs.

### Step-by-Step Boot Sequence

1. **UEFI firmware** loads and executes the unified kernel image (UKI) directly from the EFI System Partition. Since the kernel, initramfs, and command line are all embedded in the UKI, no separate bootloader is needed.[^4][^5]

2. **Kernel decompresses and initializes.** The kernel initializes hardware using built-in drivers, sets up memory management, and mounts an internal tmpfs as the root filesystem (`rootfs`).[^2]

3. **Kernel extracts the initramfs.** The embedded (or loaded) cpio archive is extracted into `rootfs`. If a file named `/init` exists, the kernel executes it as PID 1.[^6][^2]

4. **`/init` runs in early userspace.** This script mounts virtual filesystems (`/proc`, `/sys`, `/dev`), populates device nodes, and then runs `cryptsetup luksOpen` to decrypt the LUKS partition. The user is prompted for a passphrase at the console.[^3][^1]

5. **The decrypted device is mounted.** After `cryptsetup` succeeds, the decrypted block device appears at `/dev/mapper/<name>`. The init script mounts this onto a mount point like `/newroot`.[^6][^3]

6. **`switch_root` transitions to the real root.** The script cleans up virtual filesystems, then calls `exec switch_root /newroot /sbin/init`. This deletes all files from the initramfs (freeing the memory), moves the mount at `/newroot` to `/`, and executes the real init as the new PID 1.[^7][^8]

7. **The real init takes over.** OpenRC, systemd, or whichever init system is installed proceeds with normal boot — mounting remaining filesystems, starting services, etc.

### Why `switch_root` and Not `pivot_root`

For an initramfs (as opposed to the legacy initrd), `switch_root` is the correct mechanism. An initramfs lives in `rootfs`, which is a special instance of tmpfs that cannot be unmounted. `switch_root` handles this by recursively deleting all initramfs files, then moving the new root mount onto `/` and executing the real init via `exec` (so it inherits PID 1). The legacy `pivot_root` approach only works with initrd (an actual block device ramdisk), not initramfs.[^9][^10][^7]

***

## Prerequisites

### Kernel Configuration

Since the initramfs is embedded directly into the kernel (for a UKI), the following kernel options must be built-in (not as modules):[^11][^1]

```
General setup --->
    [*] Initial RAM filesystem and RAM disk (initramfs/initrd) support
    (/usr/src/initramfs) Initramfs source file(s)    # or leave blank for external cpio
    Built-in initramfs compression mode (None) --->   # recommended when embedding

Device Drivers --->
    [*] Multiple devices driver support (RAID and LVM) --->
        <*> Device mapper support
        <*> Crypt target support

Cryptographic API --->
    <*> XTS support
    <*> SHA224 and SHA256 digest algorithm
    <*> AES cipher algorithms
    <*> AES cipher algorithms (x86_64)           # for hardware acceleration
    <*> User-space interface for hash algorithms
    <*> User-space interface for symmetric key cipher algorithms
```

All crypto algorithms and the device mapper must be built-in (`<*>`, not `<M>`) because modules cannot be loaded before the initramfs runs — the initramfs *is* the earliest userspace. The block device drivers for the disk controller (NVMe, AHCI, etc.) and the filesystem driver for the root partition (ext4, btrfs, xfs, etc.) must also be built-in.[^1][^11]

When embedding the initramfs, setting the compression mode to `None` is recommended because the kernel image itself is already compressed. This avoids double-compression and actually results in smaller images and faster boot.[^1]

### Static Binaries

Two key binaries are needed, both compiled as static executables so no shared libraries are required in the initramfs:[^3][^1]

**Busybox** — Provides a shell (`sh`), `mount`, `umount`, `switch_root`, `mdev`, `sleep`, and many other utilities in a single binary.[^1]

```bash
# /etc/portage/package.use/busybox
sys-apps/busybox static -pam

emerge --ask sys-apps/busybox
ldd /bin/busybox   # should say "not a dynamic executable"
```

**cryptsetup** — The tool to open LUKS containers. Build it statically as well:[^3][^1]

```bash
# /etc/portage/package.use/cryptsetup
sys-fs/cryptsetup -gcrypt nettle static

emerge --ask sys-fs/cryptsetup
ldd /sbin/cryptsetup   # should say "not a dynamic executable"
```

If building a static `cryptsetup` proves difficult with the default `gcrypt` backend, switching to `nettle` or `kernel` crypto backend is recommended.[^1]

***

:# Building the Initramfs

### Directory Structure

Create the working directory that will become the initramfs root:[^1]

```bash
mkdir -p /usr/src/initramfs/{bin,dev,etc,lib,lib64,mnt/root,proc,root,sbin,sys,run}
```

### Device Nodes

Copy essential device nodes. These must exist before `/dev` is populated dynamically:[^3][^1]

```bash
cp -a /dev/{null,console,tty,random,urandom} /usr/src/initramfs/dev/
```

For the LUKS partition, either copy the specific block device node (e.g., `/dev/nvme0n1p2` or `/dev/sda2`) or use `devtmpfs`/`mdev` to populate devices dynamically at boot. The `devtmpfs` approach is strongly recommended because it eliminates hardcoded device paths:[^1]

```bash
# In /init, mount devtmpfs instead of copying block device nodes:
mount -t devtmpfs devtmpfs /dev
```

### Install Binaries

Copy the static binaries and create busybox symlinks:[^3][^1]

```bash
cp /bin/busybox /usr/src/initramfs/bin/busybox
cp /sbin/cryptsetup /usr/src/initramfs/sbin/cryptsetup

cd /usr/src/initramfs/bin
ln -s busybox sh
ln -s busybox mount
ln -s busybox umount
ln -s busybox switch_root
ln -s busybox sleep
ln -s busybox cat
ln -s busybox mdev
```

### The `/init` Script

This is the heart of the initramfs. Create `/usr/src/initramfs/init`:[^6][^3][^1]

(See "Advancced" section for new `init` with updates to use existing `crypt_root=UUID=` and `root=UUID=` kernel command line parameters

```bash
#!/bin/busybox sh

# -----------------------------------------------
# Minimal /init for LUKS-encrypted root
# -----------------------------------------------

export PATH="/bin:/sbin"

# Mount virtual filesystems
mount -t proc     proc     /proc
mount -t sysfs    sysfs    /sys
mount -t devtmpfs devtmpfs /dev

# Brief pause to let the kernel finish printing
sleep 1

# Rescue shell in case of failure
rescue_shell() {
    echo "Something went wrong. Dropping to a rescue shell."
    busybox --install -s /bin
    exec /bin/sh
}

# Parse kernel command line for root= and rootfstype=
root=""
rootfstype="ext4"
for param in $(cat /proc/cmdline); do
    case "$param" in
        root=*)       root="${param#root=}" ;;
        rootfstype=*) rootfstype="${param#rootfstype=}" ;;
    esac
done

# Resolve UUID= or LABEL= style root specifications
case "$root" in
    UUID=*)
        uuid="${root#UUID=}"
        root="/dev/disk/by-uuid/$uuid"
        ;;
    LABEL=*)
        label="${root#LABEL=}"
        root="/dev/disk/by-label/$label"
        ;;
esac

# Populate /dev/disk/by-uuid etc. using mdev
echo /bin/mdev > /proc/sys/kernel/hotplug
mdev -s

# Determine the LUKS device
# For a simple setup, the LUKS container is the device specified by root=
# and after decryption, the root fs is at /dev/mapper/luksroot.
# Adjust luks_device below to match your partition.
luks_device="/dev/sda2"   # <-- CHANGE THIS to your LUKS partition

# Decrypt the LUKS partition
cryptsetup --tries 5 luksOpen "$luks_device" luksroot || rescue_shell

# Mount the decrypted root filesystem
mount -t "$rootfstype" -o ro /dev/mapper/luksroot /mnt/root || rescue_shell

# Clean up
umount /proc
umount /sys
umount /dev

# Hand off to the real init
exec switch_root /mnt/root /sbin/init
```

Make it executable:[^1]

```bash
chmod +x /usr/src/initramfs/init
```

### Key Design Decisions in the Script

- **`devtmpfs`** is used instead of static device nodes, so the kernel automatically populates `/dev` with all detected block devices.[^1]
- **`mdev -s`** (busybox's lightweight udev replacement) scans `/sys` and creates symlinks like `/dev/disk/by-uuid/`, which are needed if the kernel command line uses `UUID=` notation.[^1]
- **`rescue_shell`** catches errors. If `cryptsetup` or `mount` fails, it installs all busybox applets and drops to an interactive shell for debugging.[^3][^1]
- **`exec switch_root`** uses `exec` so the real `/sbin/init` inherits PID 1 from the init script, which is required for the system to function correctly.[^7]
- The LUKS device path is hardcoded in this example. For a more flexible approach, a custom kernel parameter (e.g., `cryptdevice=`) can be parsed instead.

***

## Packaging the Initramfs

There are two approaches, depending on the workflow.

### Option A: Embed Directly into the Kernel

Set the kernel config to point at the initramfs directory:[^1]

```
General setup --->
    (/usr/src/initramfs) Initramfs source file(s)
```

Then rebuild the kernel. The build system automatically creates a cpio archive from the directory contents and embeds it into the bzImage. This is the simplest approach when building a UKI, since the kernel already contains the initramfs.[^1]

### Option B: Create a Standalone cpio Archive

Build the archive manually:[^3][^1]

```bash
cd /usr/src/initramfs
find . -print0 | cpio --null -ov --format=newc | gzip -9 > /boot/initramfs.cpio.gz
```

This produces a file that can be passed to `objcopy` when assembling a UKI, or referenced via the `initrd=` kernel parameter if using a bootloader.

### Assembling the Unified Kernel Image

Since direct UEFI booting with no bootloader is the target, combine the EFI stub, kernel, initramfs, and command line into a single `.efi` binary using `objcopy`:[^12][^13]

```bash
# Create a cmdline file
echo "root=/dev/mapper/luksroot ro rootfstype=ext4 quiet" > /tmp/cmdline.txt

# Assemble the UKI
objcopy \
    --add-section .osrel="/usr/lib/os-release"    --change-section-vma .osrel=0x20000 \
    --add-section .cmdline="/tmp/cmdline.txt"      --change-section-vma .cmdline=0x30000 \
    --add-section .linux="/boot/vmlinuz"           --change-section-vma .linux=0x2000000 \
    --add-section .initrd="/boot/initramfs.cpio.gz" --change-section-vma .initrd=0x3000000 \
    /usr/lib/systemd/boot/efi/linuxx64.efi.stub \
    /boot/efi/EFI/Gentoo/gentoo.efi
```

Alternatively, the `ukify` tool from systemd can build UKIs with a simpler interface:[^14][^15]

```bash
ukify build \
    --linux=/boot/vmlinuz \
    --initrd=/boot/initramfs.cpio.gz \
    --cmdline='root=/dev/mapper/luksroot ro rootfstype=ext4 quiet' \
    --output=/boot/efi/EFI/Gentoo/gentoo.efi
```

Register the UKI with the firmware:[^16]

```bash
efibootmgr --create --disk /dev/sda --part 1 \
    --label "Gentoo" --loader '\EFI\Gentoo\gentoo.efi'
```

***

## Complete Walkthrough Summary

The entire process from start to finish:

| Step | Action | Key Command/File |
|------|--------|-----------------|
| 1 | Enable kernel crypto and DM support as built-in | `make menuconfig` |
| 2 | Emerge static busybox and cryptsetup | `emerge busybox cryptsetup` |
| 3 | Create initramfs directory tree | `mkdir -p /usr/src/initramfs/{bin,dev,...}` |
| 4 | Copy device nodes | `cp -a /dev/{null,console,...}` |
| 5 | Copy static binaries and create symlinks | `cp /bin/busybox ...` |
| 6 | Write the `/init` script | See script above |
| 7 | Make `/init` executable | `chmod +x init` |
| 8 | Package as cpio (or embed in kernel) | `find . \| cpio ... \| gzip` |
| 9 | Assemble UKI with objcopy or ukify | `objcopy --add-section ...` |
| 10 | Register with UEFI firmware | `efibootmgr --create ...` |

***

## Troubleshooting

### "No such file or directory" for cryptsetup

This usually means the binary is dynamically linked and its libraries are missing. Verify with `ldd /sbin/cryptsetup` — it must report "not a dynamic executable".[^1]

### Kernel Panic: No init found

The kernel expects `/init` at the root of the initramfs (not `/sbin/init`). Ensure the file exists, is executable, and has a valid shebang line (`#!/bin/busybox sh`).[^2]

### cryptsetup Fails with "No key available"

The kernel's crypto subsystem is missing the required algorithms. Ensure AES, XTS, and SHA256 are compiled in (not as modules).[^17][^11]

### Device Not Found

If `/dev/sda2` or similar doesn't exist at init time, the block device driver may not be built into the kernel, or the device hasn't been enumerated yet. Using `devtmpfs` and `mdev -s` addresses the enumeration issue. For NVMe drives, ensure `CONFIG_BLK_DEV_NVME=y`.[^1]

### Debugging Technique

Add `exec /bin/sh` at any point in the `/init` script to drop into an interactive shell and inspect the environment — check what's in `/dev`, test `cryptsetup` manually, examine `dmesg` output, etc.[^3][^1]

***

## Advanced Enhancements

### Using UUID Instead of Device Path

Hardcoding `/dev/sda2` is fragile. A better approach parses a custom kernel parameter:[^18]

```bash
# In kernel cmdline: cryptdevice=UUID=<uuid>:luksroot
for param in $(cat /proc/cmdline); do
    case "$param" in
        cryptdevice=*)
            crypt_spec="${param#cryptdevice=}"
            luks_source="${crypt_spec%%:*}"
            luks_name="${crypt_spec##*:}"
            case "$luks_source" in
                UUID=*) luks_source="/dev/disk/by-uuid/${luks_source#UUID=}" ;;
            esac
            ;;
    esac
done
cryptsetup luksOpen "$luks_source" "$luks_name" || rescue_shell
```

Here is a full new version of init adapted to both `crypt_root` and `root`.

```
#!/bin/busybox sh
export PATH="/bin:/sbin"

mount -t proc     proc     /proc
mount -t sysfs    sysfs    /sys
mount -t devtmpfs devtmpfs /dev

rescue_shell() {
    echo "Dropping to rescue shell"
    busybox --install -s /bin
    exec /bin/sh
}

luks_source=""
root_spec=""
rootfstype="ext4"   # default; override via rootfstype=

for param in $(cat /proc/cmdline); do
    case "$param" in
        crypt_root=*)
            crypt_spec="${param#crypt_root=}"
            luks_source="$crypt_spec"
            case "$luks_source" in
                UUID=*)
                    luks_source="/dev/disk/by-uuid/${luks_source#UUID=}"
                    ;;
            esac
            ;;
        root=*)
            root_spec="${param#root=}"
            case "$root_spec" in
                UUID=*)
                    root_spec="/dev/disk/by-uuid/${root_spec#UUID=}"
                    ;;
            esac
            ;;
        rootfstype=*)
            rootfstype="${param#rootfstype=}"
            ;;
    esac
done

[ -z "$luks_source" ] && echo "No crypt_root= found" && rescue_shell
[ -z "$root_spec" ] && echo "No root= found" && rescue_shell

# Populate /dev/disk/by-uuid etc.
# echo /bin/mdev > /proc/sys/kernel/hotplug
mdev -s

cryptsetup luksOpen "$luks_source" luksroot || rescue_shell

# If root=UUID points directly at the decrypted fs, use that.
# If you prefer always using the mapper, you can instead hardcode /dev/mapper/luksroot.
mount -t "$rootfstype" -o ro "$root_spec" /mnt/root || rescue_shell

umount /proc
umount /sys
umount /dev

exec switch_root /mnt/root /sbin/init
```
This didn't end up working as the by-disk/uuid's weren't being populated. Went with a simpler approach for now. This script booted:
```
#!/bin/busybox sh
export PATH="/bin:/sbin"

# Mount virtual filesystems
mount -t proc     proc     /proc
mount -t sysfs    sysfs    /sys
mount -t devtmpfs devtmpfs /dev

rescue_shell() {
    echo "Dropping to rescue shell"
    exec /bin/busybox sh
}

# Find a LUKS container device by its LUKS UUID
find_luks_by_uuid() {
    target_uuid="$1"
    for dev in /dev/sd?* /dev/nvme?n?p* /dev/vd?*; do
        [ -b "$dev" ] || continue
        uuid="$(cryptsetup luksUUID "$dev" 2>/dev/null || true)"
        [ -n "$uuid" ] || continue
        [ "$uuid" = "$target_uuid" ] && { echo "$dev"; return 0; }
    done
    return 1
}

luks_uuid=""
rootfstype="ext4"

# Parse kernel command line
for param in $(cat /proc/cmdline); do
    case "$param" in
        crypt_root=UUID=*)
            luks_uuid="${param#crypt_root=UUID=}"
            ;;
        rootfstype=*)
            rootfstype="${param#rootfstype=}"
            ;;
    esac
done

[ -z "$luks_uuid" ] && echo "No crypt_root=UUID= found" && rescue_shell

# Optional: populate /dev from sysfs (not strictly required for luksUUID)
mdev -s

CRYPTSETUP=/sbin/cryptsetup
[ ! -x "$CRYPTSETUP" ] && echo "cryptsetup missing" && rescue_shell

luks_source="$(find_luks_by_uuid "$luks_uuid")" || {
    echo "Could not find LUKS device with LUKS UUID=$luks_uuid"
    rescue_shell
}

"$CRYPTSETUP" luksOpen "$luks_source" luksroot || rescue_shell

# Hardcode root as the filesystem inside the mapper
mount -t "$rootfstype" -o ro /dev/mapper/luksroot /mnt/root || rescue_shell

umount /proc
umount /sys
umount /dev

exec switch_root /mnt/root /sbin/init
```

### Keyfile Support

A LUKS keyfile can be embedded in the initramfs to avoid typing a passphrase (useful for headless servers with other physical security):[^19][^1]

```bash
cryptsetup --key-file /root/keyfile luksOpen "$luks_device" luksroot
```

The keyfile would be placed at `/usr/src/initramfs/root/keyfile` and the initramfs image must have restrictive permissions (0600) since it contains secret material.[^19]

### Plymouth or Splash Screen

For a graphical passphrase prompt, Plymouth can be included in the initramfs, though this significantly increases complexity and size — contrary to the goal of minimalism.

***

## Comparing Approaches

| Aspect | genkernel --luks | Custom Initramfs | Dracut |
|--------|-----------------|------------------|--------|
| Size | Large (~20-50 MB) | Tiny (~1-5 MB) | Medium (~10-30 MB) |
| Boot speed | Slower | Fastest | Moderate |
| Flexibility | Limited to genkernel options | Complete control | Hook-based customization |
| Maintenance | Auto-generated | Manual updates required | Semi-automatic |
| Learning curve | Low | High (but educational) | Medium |
| Gentoo-specific params | `dolvm`, `crypt_root`, etc.[^20] | Custom, self-defined | Standard `rd.luks.*` |

---

## References

1. [LUKS and Initramfs - Protean Security](https://www.proteansec.com/hacking/luks-and-initramfs/) - Since the root partition is encrypted, it has to be decrypted during the boot process, which is not ...

2. [Ramfs, rootfs and initramfs](https://docs.kernel.org/filesystems/ramfs-rootfs-initramfs.html) - After extracting, the kernel checks to see if rootfs contains a file “init”, and if so it executes i...

3. [Minimal initramfs for LUKS and LVM - deaddy.net](https://deaddy.net/minimal-initramfs-for-luks-and-lvm.html) - Now we may begin by creating the initramfs, so as root we create a folder. All of the following take...

4. [Unified kernel image - ArchWiki](https://wiki.archlinux.org/title/Unified_kernel_image) - A unified kernel image (UKI) is a single executable which can be booted directly from UEFI firmware,...

5. [Unified Kernel Image (UKI) - Athena OS](https://athenaos.org/en/security/uki/) - A Unified Kernel Image (UKI) is a single, signed EFI executable that contains all components needed ...

6. [initramfs: The Initial RAM Filesystem Explained - Abhik Sarkar](https://www.abhik.ai/concepts/linux/initramfs-boot-process) - What is initramfs? initramfs (initial RAM filesystem) is a temporary root filesystem loaded into mem...

7. [Changing the root of your Linux filesystem | Marcus Folkesson Blog](https://www.marcusfolkesson.se/blog/changing-the-root-of-your-linux-filesystem/) - The typical use of pivot_root() is during system startup, when the system mounts a temporary root fi...

8. [HowTo/initramfs - Source Mage GNU/Linux](http://sourcemage.org/HowTo/initramfs) - Busybox provides switch_root to accomplish this, while klibc offers new_root . ... Call resume from ...

9. [tc boot /init switch_root - Tiny Core Linux](https://forum.tinycorelinux.net/index.php/topic,22449.0.html) - initramfs is not a file system. For initrd pivot_root is used and for initramfs switch_root is used.

10. [Programming for initramfs - Rob Landley](https://landley.net/writing/rootfs-programming.html) - What switch_root does is delete all the files out of rootfs (to free up the memory) and then chroot ...

11. [Cryptsetup & dm-crypt - Paul's Linux Box](https://paulslinuxbox.net/articles/2018/04/07/cryptsetup-dm-crypt/) - cryptsetup is a command line tool that interfaces with the dm_crypt kernel module that creates, acce...

12. [Of EFIStub, directboot and systemd-boot... - archlinux - Reddit](https://www.reddit.com/r/archlinux/comments/up8h6l/of_efistub_directboot_and_systemdboot/) - Looks like EFISTUB's cmdline parameters are passed through an EFIVar, while unified images have it e...

13. [EFIStub - Debian Wiki](https://wiki.debian.org/EFIStub) - To set up EFIStub, you need to first copy the kernel and initrd into the EFI system partition, then ...

14. [ukify - Combine components into a signed Unified Kernel Image for ...](https://manpages.ubuntu.com/manpages/noble/man1/ukify.1.html) - ukify is a tool whose primary purpose is to combine components (usually a kernel, an initrd, and a U...

15. [ukify(1) - Linux manual page - man7.org](https://man7.org/linux/man-pages/man1/ukify.1.html) - The following commands are understood: build This command creates a Unified Kernel Image. The two pr...

16. [Setup a boot process where the kernel is stored on encrypted root.](https://bbs.archlinux.org/viewtopic.php?id=286702) - I found a better solution: -using a Unified Kernel Image -sign it with secure boot -manually registe...

17. [linux: Kernel is missing modules required to boot LVM/LUKS #720](https://github.com/void-linux/void-packages/issues/720) - At boot time, an error is thrown saying the module "dm_crypt" is not found, and dracut complains abo...

18. [Debian Cryptsetup Initramfs integration](https://cryptsetup-team.pages.debian.net/cryptsetup/README.initramfs.html) - In order to boot from an encrypted root filesystem, you need an initramfs-image which includes the n...

19. [Full disk encryption, including /boot: Unlocking LUKS devices from ...](https://cryptsetup-team.pages.debian.net/cryptsetup/encrypted-boot.html) - The device(s) holding /boot needs to be in LUKS format version 1 to be unlocked from the boot loader...

20. [Confused about genkernel and dracut, Luks LVM. : r/Gentoo - Reddit](https://www.reddit.com/r/Gentoo/comments/1awvtwo/confused_about_genkernel_and_dracut_luks_lvm/) - I'm having trouble getting this to work. I managed to install it once by luck, just trying different...

