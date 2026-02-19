# StarFighter Kernel Optimization Plan

## Current State Summary

Your kernel (6.18.8-gentoo) was built from `make localmodconfig` with many generic distribution defaults still enabled. Key observations from your hardware and config files:[^1]

- **CPU**: Intel Core Ultra 9 285H — 16 cores (6P+8E+2LP-E), no SMT, Arrow Lake-H, model 0xC5, family 6[^2]
- **GPU**: Intel integrated only (Arrow Lake-P / Meteor Lake display), currently driven by **i915** (xe loaded but unused)[^3][^4]
- **Storage**: Two NVMe SSDs (Samsung 990 PRO + 970 EVO), LUKS dm-crypt on nvme1n1p2, EXT4 root[^5][^6]
- **Network**: Intel AX210 Wi-Fi (iwlwifi/iwlmvm), Intel Bluetooth (btusb/btintel)[^4][^3]
- **Input**: I2C HID touchpad (STAR0001), PS/2 keyboard (i8042)[^5]
- **Audio**: HDA Intel PCH with ALC233 codec, HDMI audio via i915[^5]
- **Firmware**: coreboot, EFI stub boot, no traditional bootloader[^1]
- **Virtualization**: KVM (kvm + kvm_intel modules loaded, currently unused)[^4]
- **Sleep**: s2idle + deep (S3) both available[^7]
- **NR_CPUS**: 8192 (wildly oversized), MAXSMP enabled[^8]
- **Loaded modules**: ~100+, including both i915 and xe, many SOF audio modules, full Xen guest stack, full SCSI subsystem[^4]

The config carries enormous amounts of unused code: Xen PV/HVM guest support, AMD CPU/GPU support, AMD pstate, NUMA across 1024 nodes, SCSI disk/CD/tape, dozens of security modules (SELinux, SMACK, TOMOYO, AppArmor, IPE), full ftrace/kgdb/KFENCE/UBSAN debugging, 3 I/O schedulers, 7 partition types you'll never use, and more.[^8]

***

## Phase 0: Preparation & Safety Net

Before touching anything, set up a rollback path.

### Step 0.1 — Save current working config as a defconfig

```bash
cd /usr/src/linux
cp .config /root/kernel-config-6.18.8-working-backup
make savedefconfig
cp defconfig /root/defconfig-6.18.8-working
```

**Justification**: You can always restore a known-good kernel by copying this defconfig back. Since you use EFI stub boot, keeping the old bzImage as a fallback EFI entry is trivial.[^1]

### Step 0.2 — Create a fallback EFI boot entry

```bash
cp /boot/EFI/boot/bootx64.efi /boot/EFI/boot/bootx64-backup.efi
efibootmgr --create --disk /dev/nvme0n1 --part 1 \
  --label "gentoo-backup" --loader /EFI/boot/bootx64-backup.efi
```

**Justification**: If the new kernel fails to boot, select "gentoo-backup" from coreboot's EFI boot menu.[^1]

***

## Phase 1: CPU & Platform Targeting

These changes give the single largest reduction in kernel bloat and improve performance by letting the compiler target your exact CPU.

### notes

- dist size:   22360064
- initrd-dist: 12882204
- begin size:  26746880 (4766912 is initrd)
- after size:  26194944

### Step 1.1 — Set processor type to Intel Core (not generic x86-64)

```
CONFIG_PROCESSOR_SELECT=y        # (enable the menu)
CONFIG_CPU_SUP_INTEL=y
# CONFIG_CPU_SUP_AMD is not set
# CONFIG_CPU_SUP_HYGON is not set
# CONFIG_CPU_SUP_CENTAUR is not set
# CONFIG_CPU_SUP_ZHAOXIN is not set
```

**Justification**: You have an Intel-only system. Disabling AMD/Hygon/Centaur/Zhaoxin removes workarounds, microcode paths, and vendor-specific code that can never execute on your hardware.[^2]

### Step 1.2 — Reduce NR_CPUS from 8192 to 16

```
# CONFIG_MAXSMP is not set
CONFIG_NR_CPUS=16
```

**Justification**: Your CPU has exactly 16 logical CPUs (no SMT). NR_CPUS=8192 wastes memory on per-CPU data structures (dmesg shows `setup_percpu: NR_CPUS:8192` allocating for just 16). This single change reduces per-CPU allocation overhead from ~12MB to ~24KB and speeds up any per-CPU iteration.[^2][^5]

### Step 1.3 — Disable NUMA

```
# CONFIG_NUMA is not set
# CONFIG_AMD_NUMA is not set
# CONFIG_X86_64_ACPI_NUMA is not set
# CONFIG_ACPI_NUMA is not set
# CONFIG_ACPI_HMAT is not set
# CONFIG_NUMA_BALANCING is not set
```

**Justification**: dmesg shows "No NUMA configuration found / Faking a node". This is a single-socket laptop with one memory controller. NUMA code adds overhead to every memory allocation path with zero benefit here.[^5]

### Step 1.4 — Disable AMD-specific subsystems

```
# CONFIG_X86_AMD_PSTATE is not set
# CONFIG_AMD_MEM_ENCRYPT is not set
# CONFIG_AMD_NB is not set
# CONFIG_KVM_AMD is not set
# CONFIG_KVM_AMD_SEV is not set
# CONFIG_X86_MCE_AMD is not set
# CONFIG_PERF_EVENTS_AMD_UNCORE is not set
# CONFIG_PERF_EVENTS_AMD_BRS is not set
# CONFIG_AMD_SECURE_AVIC is not set
```

**Justification**: This is an Intel system. All AMD paths are dead code.[^2]

### Step 1.5 — Target the native CPU with march=native (already doing this)

Your build command already uses `KCFLAGS="-march=native -O2 -pipe"`. This is correct and generates optimal code for Arrow Lake. Keep it.

***

## Phase 2: Remove Hypervisor Guest Support

Your system boots on bare metal with coreboot. All guest/paravirt code is wasted.[^5]

### notes

- begin size: 26194944
- after size: 25785344

### Step 2.1 — Disable all hypervisor guest code

```
# CONFIG_HYPERVISOR_GUEST is not set
# CONFIG_PARAVIRT is not set
# CONFIG_PARAVIRT_XXL is not set
# CONFIG_PARAVIRT_SPINLOCKS is not set
# CONFIG_XEN is not set
# CONFIG_KVM_GUEST is not set
# CONFIG_ACRN_GUEST is not set
# CONFIG_BHYVE_GUEST is not set
# CONFIG_INTEL_TDX_GUEST is not set
# CONFIG_PVH is not set
# CONFIG_PARAVIRT_TIME_ACCOUNTING is not set
# CONFIG_PARAVIRT_CLOCK is not set
# CONFIG_PCI_XEN is not set
```

**Justification**: dmesg confirms "Booting paravirtualized kernel on bare hardware" — the paravirt framework is active but doing nothing useful. Xen PV/HVM, KVM guest, ACRN, bhyve, TDX guest are all irrelevant on a laptop running as a host. Removing this eliminates a large amount of code and the paravirt indirect-call overhead in hot paths.

### Step 2.2 — Remove Xen-specific subsystems entirely

```
# CONFIG_XEN_BALLOON is not set
# CONFIG_XEN_BACKEND is not set
# CONFIG_XEN_SYS_HYPERVISOR is not set
# CONFIG_XEN_XENBUS_FRONTEND is not set
# CONFIG_SWIOTLB_XEN is not set
# CONFIG_XEN_EFI is not set
# CONFIG_XEN_VIRTIO is not set
# CONFIG_HVC_XEN is not set
# CONFIG_HVC_XEN_FRONTEND is not set
# CONFIG_XEN_BLKDEV_BACKEND is not set (verify already unset)
```

**Justification**: Your lsmod shows zero Xen modules loaded. These are guest-side drivers for a hypervisor you're not running under.

### Step 2.3 — Remove Hyper-V guest support

```
# CONFIG_HYPERV is not set
# CONFIG_HYPERV_TIMER is not set
# CONFIG_HYPERV_IOMMU is not set
```

**Justification**: Not running under Hyper-V.

***

## Phase 3: Right-Size KVM Host Virtualization

You want host virtualization. Keep KVM and KVM_INTEL as modules, but trim the extras.

- begin size: 25785344
- after size: 25887744

### Step 3.1 — Clean KVM configuration

```
CONFIG_VIRTUALIZATION=y
CONFIG_KVM=m
CONFIG_KVM_INTEL=m
CONFIG_KVM_X86=m

# Reduce vCPU limit from 4096 to something sane
CONFIG_KVM_MAX_NR_VCPUS=256

# Keep IOMMU/VT-d for device passthrough
CONFIG_INTEL_IOMMU=y
CONFIG_INTEL_IOMMU_SVM=y
CONFIG_IRQ_REMAP=y
CONFIG_VFIO=m    # Enable if you want GPU/device passthrough

# Disable features you don't need:
# CONFIG_KVM_SMM is not set           # SMM emulation — not needed for modern guests
# CONFIG_KVM_HYPERV is not set        # Hyper-V enlightenments for Windows guests (re-enable if needed)
# CONFIG_KVM_XEN is not set           # Xen emulation inside KVM
# CONFIG_KVM_SW_PROTECTED_VM is not set
# CONFIG_X86_SGX_KVM is not set       # SGX in guests — very niche
# CONFIG_KVM_INTEL_TDX is not set     # TDX confidential VMs — datacenter feature
# CONFIG_KVM_PROVE_MMU is not set
```

**Justification**: MAX_NR_VCPUS=4096 is datacenter-scale. 256 is more than generous for a laptop host. KVM_HYPERV, KVM_XEN, SGX_KVM, and TDX are enterprise features with significant code footprint that you won't use for typical desktop/development VMs. If you later run Windows VMs and want better performance, re-enable KVM_HYPERV.[^8]

### Step 3.2 — virtio devices for guests

```
CONFIG_VIRTIO=y
CONFIG_VIRTIO_PCI=y
CONFIG_VIRTIO_BLK=y
CONFIG_VIRTIO_NET=m
CONFIG_VHOST=m
CONFIG_VHOST_NET=m
```

**Justification**: These are needed for efficient I/O in KVM guests. Keep as modules so they only load when VMs are running.

***

## Phase 4: Graphics Driver Cleanup

### Step 4.1 — Choose i915 only, disable xe

```
CONFIG_DRM_I915=m
# CONFIG_DRM_XE is not set
```

**Justification**: Your lsmod shows i915 is the active driver (used by 27 dependents) while xe is loaded with 0 users. On Arrow Lake / Meteor Lake display hardware, i915 is the mature, stable driver. xe is the future replacement but not yet primary for your GPU generation. Removing xe eliminates a 4.3MB module and its dependencies (drm_gpuvm, drm_gpusvm_helper, gpu_sched) from loading.[^4]

### Step 4.2 — Remove unused DRM drivers

Verify and ensure all non-Intel DRM drivers are disabled (nouveau, amdgpu, radeon, etc.). These should already be off from localmodconfig but double-check.

***

## Phase 5: Storage & Filesystem Trimming

### Step 5.1 — Remove SCSI/ATA/SATA (you have zero SATA devices)

```
# CONFIG_ATA is not set
# CONFIG_SCSI is not set        # Note: this may need to stay if anything depends on it
# CONFIG_BLK_DEV_SD is not set
# CONFIG_BLK_DEV_SR is not set
# CONFIG_CHR_DEV_SG is not set
```

**Justification**: Your system has only NVMe storage. There are no SATA/AHCI ports in use (no SATA controller in lspci). The SCSI midlayer, libata, AHCI, ata_piix are all dead code. dmesg shows "libata version 3.00 loaded" for no reason. If `CONFIG_SCSI` is needed as a dependency for something (unlikely with NVMe-only), keep it minimal.[^6][^3][^5]

**Caveat**: If you ever use USB mass storage devices (USB drives, phone MTP), you may need `CONFIG_USB_STORAGE` which depends on SCSI. In that case, keep SCSI core but disable all SCSI low-level drivers and ATA.

### Step 5.2 — Keep only needed filesystems

```
CONFIG_EXT4_FS=y                # Your root filesystem
CONFIG_BTRFS_FS=y               # Keep if you use it on the other drive
# CONFIG_XFS_FS is not set      # Remove unless actively used
CONFIG_VFAT_FS=y                # Needed for EFI System Partition
CONFIG_FUSE_FS=m                # Keep for FUSE mounts
CONFIG_TMPFS=y
CONFIG_PROC_FS=y
CONFIG_SYSFS=y
```

**Justification**: dmesg shows EXT4 mounting dm-0. XFS is compiled in but nothing in your system uses it (dmesg shows "SGI XFS" loading but no XFS mounts). Btrfs is loaded — keep only if used on nvme0n1. Each filesystem adds substantial code.[^5]

### Step 5.3 — Remove exotic partition types

```
# CONFIG_AIX_PARTITION is not set
# CONFIG_OSF_PARTITION is not set
# CONFIG_MAC_PARTITION is not set
# CONFIG_BSD_DISKLABEL is not set
# CONFIG_MINIX_SUBPARTITION is not set
# CONFIG_SOLARIS_X86_PARTITION is not set
# CONFIG_UNIXWARE_DISKLABEL is not set
# CONFIG_LDM_PARTITION is not set
# CONFIG_SGI_PARTITION is not set
# CONFIG_SUN_PARTITION is not set
CONFIG_MSDOS_PARTITION=y         # Keep for compatibility
CONFIG_EFI_PARTITION=y           # Required for GPT
```

**Justification**: Your drives use GPT. AIX, OSF, Mac, BSD, Minix, Solaris, UnixWare, LDM, SGI, Sun partitions will never appear on this system.[^6][^8]

### Step 5.4 — Trim I/O schedulers

```
CONFIG_MQ_IOSCHED_DEADLINE=y
# CONFIG_MQ_IOSCHED_KYBER is not set
# CONFIG_IOSCHED_BFQ is not set
```

**Justification**: For NVMe SSDs, `mq-deadline` or `none` are optimal. BFQ and Kyber add code with no benefit on fast NVMe. dmesg shows all three registered unnecessarily.[^8][^5]

***

## Phase 6: Networking Cleanup

### Step 6.1 — Remove unused network protocols and drivers

```
# CONFIG_HAMRADIO is not set
# CONFIG_NET_NCSI is not set
# CONFIG_MCTP is not set
# CONFIG_MPLS is not set
# CONFIG_DCB is not set
# All CONFIG_NET_VENDOR_* for unused vendors — disable
# CONFIG_8021Q is not set        # VLAN — unless you actively use VLANs
```

**Justification**: Ham radio, NCSI, MCTP, MPLS, DCB are enterprise/embedded networking protocols irrelevant to a laptop. 802.1Q VLAN is loaded but probably unused unless you have VLAN-tagged networks.[^4][^8]

### Step 6.2 — Trim wireless drivers to Intel only

Your config already has `CONFIG_IWLWIFI=m` and `CONFIG_IWLMVM=m`, which is correct. Verify all other wireless vendor drivers are disabled (Atheros, Broadcom, Realtek, MediaTek, Ralink, etc.). Many `WLAN_VENDOR_*` options are enabled as containers but should have no actual drivers under them.[^8]

***

## Phase 7: Audio Cleanup

### Step 7.1 — Keep only needed audio paths

```
CONFIG_SND_HDA_INTEL=m
CONFIG_SND_HDA_CODEC_REALTEK=m   # ALC233 codec
CONFIG_SND_HDA_CODEC_HDMI=m      # HDMI audio via i915
CONFIG_SND_HDA_CODEC_GENERIC=m

# Disable Sound Open Firmware (SOF) if HDA works:
# CONFIG_SND_SOC_SOF_TOPLEVEL is not set
```

**Justification**: Your audio works via the legacy HDA path (snd_hda_intel drives the codec). lsmod shows the SOF stack is loaded (snd_sof_pci_intel_mtl etc.) with 0 users — it's autoloaded but not actually servicing audio. The SOF modules account for ~1MB of loaded code doing nothing. Disabling SOF is safe since HDA is working. If you encounter issues with HDMI audio or after a kernel update, you can re-enable it.[^4][^5]

***

## Phase 8: Security Module Cleanup

### Step 8.1 — Remove unused security modules

```
# CONFIG_SECURITY_SELINUX is not set
# CONFIG_SECURITY_TOMOYO is not set     (currently configured)
# CONFIG_SECURITY_IPE is not set
# CONFIG_SECURITY_LANDLOCK is not set    (keep if you want sandboxing)

# Keep only what you use:
CONFIG_SECURITY=y
CONFIG_SECURITY_YAMA=y
CONFIG_SECURITY_PATH=y
CONFIG_SECCOMP=y
CONFIG_SECCOMP_FILTER=y
```

**Justification**: dmesg shows LSM initializing "capability,landlock,yama,bpf,ima,evm" but systemd reports "-SELINUX -APPARMOR". SELinux, SMACK, TOMOYO, AppArmor, and IPE are all compiled in but completely unused. Each adds significant code, hook overhead, and xattr processing. IMA/EVM can also be removed unless you have a specific integrity measurement requirement.[^5]

### Step 8.2 — Consider removing IMA/EVM

```
# CONFIG_IMA is not set
# CONFIG_EVM is not set
```

**Justification**: dmesg shows "ima: No architecture policies found". IMA is initialized but doing nothing useful without configured policies. It adds overhead to every file open.[^5]

***

## Phase 9: Debug & Tracing Reduction

This is one of the biggest wins for kernel size and boot speed.

### Step 9.1 — Disable KFENCE

```
# CONFIG_KFENCE is not set
```

**Justification**: KFENCE is a sampling memory error detector for development. dmesg shows it reserving 2MB of RAM for 255 objects. Unnecessary for a production system.[^5]

### Step 9.2 — Reduce ftrace/tracing

```
# CONFIG_FUNCTION_TRACER is not set
# CONFIG_FUNCTION_GRAPH_TRACER is not set
# CONFIG_SCHED_TRACER is not set
# CONFIG_HWLAT_TRACER is not set
# CONFIG_OSNOISE_TRACER is not set
# CONFIG_TIMERLAT_TRACER is not set
# CONFIG_MMIOTRACE is not set
# CONFIG_BLK_DEV_IO_TRACE is not set
# CONFIG_STACK_TRACER is not set
# CONFIG_FUNCTION_PROFILER is not set
```

Keep `CONFIG_FTRACE=y` and `CONFIG_EVENT_TRACING=y` (needed by perf/BPF), but disable the heavyweight tracers.

**Justification**: dmesg shows "ftrace allocating 66618 entries in 262 pages" — that's ~1MB just for the ftrace trampolines. The full function tracer, graph tracer, and various latency tracers are development tools. Event tracing alone is sufficient for perf and BPF.[^5]

### Step 9.3 — Disable KGDB

```
# CONFIG_KGDB is not set
# CONFIG_KGDB_SERIAL_CONSOLE is not set
# CONFIG_KGDB_TESTS is not set
```

**Justification**: Kernel debugger. Not needed on a production laptop.[^8]

### Step 9.4 — Disable UBSAN

```
# CONFIG_UBSAN is not set
```

**Justification**: Undefined Behavior Sanitizer adds runtime checks and code to every function. It's a development/CI tool.[^8]

### Step 9.5 — Reduce debug info

```
CONFIG_DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT=y
# CONFIG_DEBUG_INFO_BTF is not set       # Disable unless you use BPF CO-RE programs
CONFIG_DEBUG_INFO_COMPRESSED_ZLIB=y       # Keep if you want debuginfo, at least compress
# CONFIG_DEBUG_INFO_BTF_MODULES is not set
```

**Justification**: BTF adds to build time and module size. If you use advanced BPF tools (bpftrace, libbpf CO-RE), keep it. Otherwise remove. Note: some systemd features may want BTF; test before committing.[^8]

### Step 9.6 — Disable other debug options

```
# CONFIG_PM_DEBUG is not set
# CONFIG_PM_TEST_SUSPEND is not set
# CONFIG_PM_SLEEP_DEBUG is not set
# CONFIG_PM_TRACE is not set
# CONFIG_PM_TRACE_RTC is not set
# CONFIG_ACPI_DEBUG is not set
# CONFIG_DEBUG_BUGVERBOSE is not set
# CONFIG_PROVIDE_OHCI1394_DMA_INIT is not set
# CONFIG_X86_DECODER_SELFTEST is not set
# CONFIG_RCU_TRACE is not set
# CONFIG_DYNAMIC_DEBUG is not set
# CONFIG_DYNAMIC_DEBUG_CORE is not set
# CONFIG_IKCONFIG is not set         # /proc/config.gz — nice to have but adds ~50KB
# CONFIG_IKCONFIG_PROC is not set
# CONFIG_MODULE_DEBUGFS is not set
# CONFIG_BLK_DEBUG_FS is not set
# CONFIG_CFG80211_DEBUGFS is not set
# CONFIG_MAC80211_DEBUGFS is not set
# CONFIG_IWLWIFI_DEBUG is not set
# CONFIG_IWLWIFI_DEBUGFS is not set
# CONFIG_DEBUG_WX is not set
# CONFIG_PT_DUMP is not set
```

**Justification**: PM_DEBUG, PM_TEST_SUSPEND, ACPI_DEBUG, RCU_TRACE, DYNAMIC_DEBUG etc. are all diagnostic tools that add code and runtime overhead. The iwlwifi/cfg80211/mac80211 debugfs adds interface clutter and code. Remove them all for a production kernel.[^8]

**Exception**: Keep `CONFIG_IKCONFIG=y` / `CONFIG_IKCONFIG_PROC=y` if you value being able to extract your running config via `/proc/config.gz`. It's small and very useful for administration simplicity. Your call.

***

## Phase 10: Miscellaneous Cleanup

### Step 10.1 — Remove unused input/HID drivers

```
# CONFIG_INPUT_JOYSTICK is not set
# CONFIG_INPUT_TABLET is not set
# CONFIG_INPUT_TOUCHSCREEN is not set    # Your touchpad is I2C HID, not a touchscreen driver
# CONFIG_INPUT_PCSPKR is not set         # PC speaker beeper — remove if you don't want beeps
```

**Justification**: No joystick, tablet, or touchscreen hardware present. The PC speaker module is loaded but likely unwanted on a modern system.[^3][^4]

### Step 10.2 — Remove Android Binder

```
# CONFIG_ANDROID_BINDER_IPC is not set
# CONFIG_ANDROID_BINDERFS is not set
```

**Justification**: Android Binder is enabled with 3 devices configured. Unless you're running Waydroid or an Android container, this is completely unused.[^8]

### Step 10.3 — Disable unused serial ports

```
CONFIG_SERIAL_8250_NR_UARTS=4          # Down from 32
CONFIG_SERIAL_8250_RUNTIME_UARTS=4     # Down from 32
# CONFIG_SERIAL_8250_MANY_PORTS is not set
# CONFIG_SERIAL_8250_RSA is not set
# CONFIG_SERIAL_NONSTANDARD is not set
```

**Justification**: 32 serial ports is wildly excessive for a laptop. You have one UART (ttyS4 for Serial IO).[^5][^8]

### Step 10.4 — Disable PMIC opregion drivers

```
# CONFIG_BYTCRC_PMIC_OPREGION is not set
# CONFIG_CHTCRC_PMIC_OPREGION is not set
# CONFIG_XPOWER_PMIC_OPREGION is not set
# CONFIG_CHTWC_PMIC_OPREGION is not set
# CONFIG_CHTDC_TI_PMIC_OPREGION is not set
```

**Justification**: These are for Bay Trail/Cherry Trail tablet PMICs. Completely irrelevant to Arrow Lake.[^8]

### Step 10.5 — Remove Staging drivers

```
# CONFIG_STAGING is not set
```

**Justification**: Staging drivers are experimental/unfinished. None are needed.[^8]

### Step 10.6 — Consider disabling hibernation

```
# CONFIG_HIBERNATION is not set
```

**Justification**: If you only use s2idle/S3 sleep (which your system supports) and never hibernate, removing this simplifies suspend paths and removes the snapshot device code. Keep if you want hibernate-to-disk capability.[^7]

### Step 10.7 — Disable crash dump

```
# CONFIG_CRASH_DUMP is not set
# CONFIG_KEXEC is not set
# CONFIG_KEXEC_FILE is not set
# CONFIG_KEXEC_JUMP is not set
```

**Justification**: kdump/kexec is a server crash analysis tool. On a laptop you'll just reboot. Removing this saves significant code.[^8]

***

## Phase 11: Power Optimization Settings

### Step 11.1 — Enable workqueue power-efficient mode

```
CONFIG_WQ_POWER_EFFICIENT_DEFAULT=y
```

**Justification**: Currently disabled in your config ("CONFIG_WQ_POWER_EFFICIENT_DEFAULT is not set"). This makes workqueues prefer power-efficient (non-bound) scheduling, reducing unnecessary CPU wakeups — a meaningful win on battery.[^8]

### Step 11.2 — Timer frequency

Your config uses HZ=300. This is a reasonable middle ground. For a laptop with Hyprland, HZ=300 is fine. You could consider HZ=250 for marginally better power, but the difference is negligible with `CONFIG_NO_HZ_FULL` / tickless behavior.[^8]

***

## Phase 12: Revised Build Process

### Step 12.1 — Updated build workflow

```bash
cd /usr/src/linux

# Start from your saved defconfig (after applying changes above)
cp /root/defconfig-starfighter .config
make olddefconfig

# Set embedded command line
# (Already in defconfig, but verify)
# CONFIG_CMDLINE="root=UUID=... crypt_root=UUID=... ro root_trim=yes"
# CONFIG_CMDLINE_OVERRIDE=y

# Build
KCFLAGS="-march=native -O2 -pipe" make -j16    # Use all 16 cores, not 12

# Install modules (stripped)
make modules_install INSTALL_MOD_STRIP=1

# Generate initrd
genkernel --luks initramfs

# Copy initrd
cp /var/tmp/genkernel/initramfs-*.cpio.xz /root/initrd-starfighter.cpio.xz

# Set initramfs source and rebuild
# (CONFIG_INITRAMFS_SOURCE="/root/initrd-starfighter.cpio.xz" in .config)
make olddefconfig
KCFLAGS="-march=native -O2 -pipe" make -j16

# Install
cp arch/x86/boot/bzImage /boot/EFI/boot/bootx64.efi
```

**Changes from current process**:[^1]
- Use `-j16` instead of `-j12` to use all available cores
- Save and restore from a proper defconfig rather than relying on localmodconfig
- Consider `make localmodconfig` only as a *starting point* for a new kernel version, then merge with your defconfig

### Step 12.2 — Save the new defconfig

```bash
make savedefconfig
cp defconfig /root/defconfig-starfighter
```

**Justification**: A `savedefconfig` produces a minimal diff from defaults — easy to read, easy to version control, and portable across kernel versions. This is the proper Gentoo/upstream way to maintain a custom config.[^1]

***

## Implementation Order (Recommended)

Apply changes in this order, rebooting and testing between each batch:

1. **Batch 1** (lowest risk, biggest impact): Phase 1 (CPU targeting, NR_CPUS) + Phase 2 (remove guest code) + Phase 10.5 (staging)
2. **Batch 2**: Phase 5 (storage/FS trimming) + Phase 6 (network cleanup) + Phase 10 (misc)
3. **Batch 3**: Phase 9 (debug/tracing reduction) + Phase 8 (security modules)
4. **Batch 4**: Phase 3 (KVM right-sizing) + Phase 4 (graphics — xe removal)
5. **Batch 5**: Phase 7 (audio — SOF removal, test carefully) + Phase 11 (power)

***

## Expected Results

| Metric | Before | After (estimated) |
|---|---|---|
| NR_CPUS | 8192 | 16 |
| Loaded modules | ~100+ | ~50-60 |
| bzImage size | ~12-14MB | ~8-10MB |
| Per-CPU allocation | ~12MB | ~24KB |
| ftrace entries | 66,618 | 0 (event-only) |
| KFENCE RAM | 2MB | 0 |
| Boot time to systemd | ~11s | ~8-9s (est.) |
| Module load overhead | High (xe, SOF, SCSI) | Reduced significantly |

The primary gains are in memory efficiency (NR_CPUS, KFENCE, per-CPU), boot speed (fewer modules to probe, less init code), and reduced attack surface (fewer security modules, no guest code, no debug interfaces).[^4][^5][^8]

---

## References

1. [notes-kernel-install.txt](https://ppl-ai-file-upload.s3.amazonaws.com/web/direct-files/collection_05e0d332-5b67-43a5-8ccf-c47e1dc1a1e1/49b13844-6e15-4b52-ac87-54eaa0aff7c5/notes-kernel-install.txt?AWSAccessKeyId=ASIA2F3EMEYEUCKJPE7P&Signature=4XIoc3LJDvpN4iliY9WM3flGFpQ%3D&x-amz-security-token=IQoJb3JpZ2luX2VjELn%2F%2F%2F%2F%2F%2F%2F%2F%2F%2FwEaCXVzLWVhc3QtMSJGMEQCIAHcs%2B3z61CmhRtndOHUTduizKIfkm%2FueSlagsj0ucgvAiBdMhT6WgNnJN7xDE4VtyeBX%2BK%2Bq%2FVje2eCNj4Tamipcir8BAiB%2F%2F%2F%2F%2F%2F%2F%2F%2F%2F8BEAEaDDY5OTc1MzMwOTcwNSIM%2Bhgt3IcpdHIXuWOIKtAEAgMqHHx%2Buo2ct0ilrTS%2B3jYvYvOwz8GFodHSHznQz%2Fi8uKcKkRR8jo0%2BQTaO3ik7APllhYVzpMEBGOliRFwXuQeFNgrxbrWlu%2FR5gCnz%2F4reZl9mtPCj%2BA1YaBanxqP6f35ajfg7gSX%2FR40FSbPRfWlqkrAYW73kJMlW%2BQfQTN8uKAc2zGom8Myp7U%2BcSdvVGeYYd7YshoodgtO%2BnG8mmib8zzvpIjUN7bxpsjV9zpomP5SqITjDmcVjIkrXsCvrfIIV3B4LYD0i1IJCH24jxojodj2tAoUMCAV9YZldYvdnFJcMWML20WpAj7CMHlzkJE2kIwhAmvqZH2zwWmssnuMZnIxLwJWMUQyPq3aNFptBRFM7tO5YEeGe2dCc3dsDNd%2F5ynPTYh7DIGHDsXqnUdlA11dED%2FQYNtTWzRr%2BVVumWQEh7KE%2FKBaktz3B5JITdq52szkNrNC79SV3nJxDm4YGg1Uzhpvsm%2Frz%2BmpxIaZgtE1WwqEx9xescDzO0qNZSDDjdEdFH3V%2F1m9uKulemPI1cN1DQiMMe9sPRPYQoNaT2YXyl%2BKjlxe5okNpqNYMVU4oDERcONbJiQIpU5jjSa6ARLfC6lu3M9Qfp1C1BcV5fzds0wMaHsvUO3DAakLPayXwv4euWibhHVriaLNuftp9TTfGMsO3qYTDCa%2BNtAxdvF4ZHDTogKXwwTjZrkEVdBliTB%2BaH5EcvQ%2B4YD6Ft9WObiCI4Nn%2FhzaTvk2RcRg9HoIS%2Bn1czVsxhqk4jTHIIBy95siqZghF9edByZj5GTCw6dzMBjqZAVOKTWYXz0cZz9i35I2XreHckkyp5NgUoaJ2%2F2qIpm%2FieoBQf5jQVLOJXk2auSy94t%2BKgxMCtaSBPvPkH2RHuMpjAOzOT5yFZ2wVLQqg8NlzGqd3t1pD6FhiAUJAaYPCfYh0FM2vPNzFZGJEhyaV1kBJPqKUHvIjd0hRXpIxxsztBSQISF2t8Yize0ncRf7gCJ1edCwYm%2BjlIw%3D%3D&Expires=1771521931) - Describe (or paste) how you build and install your EFI stub kernel here.

Here are the steps:

- if ...

2. [lscpu.txt](https://ppl-ai-file-upload.s3.amazonaws.com/web/direct-files/collection_05e0d332-5b67-43a5-8ccf-c47e1dc1a1e1/e5e0751c-f18b-486a-b6ba-b1456630c570/lscpu.txt?AWSAccessKeyId=ASIA2F3EMEYEUCKJPE7P&Signature=DpZeq85H9zsp%2FqEFW6uvDku3DJM%3D&x-amz-security-token=IQoJb3JpZ2luX2VjELn%2F%2F%2F%2F%2F%2F%2F%2F%2F%2FwEaCXVzLWVhc3QtMSJGMEQCIAHcs%2B3z61CmhRtndOHUTduizKIfkm%2FueSlagsj0ucgvAiBdMhT6WgNnJN7xDE4VtyeBX%2BK%2Bq%2FVje2eCNj4Tamipcir8BAiB%2F%2F%2F%2F%2F%2F%2F%2F%2F%2F8BEAEaDDY5OTc1MzMwOTcwNSIM%2Bhgt3IcpdHIXuWOIKtAEAgMqHHx%2Buo2ct0ilrTS%2B3jYvYvOwz8GFodHSHznQz%2Fi8uKcKkRR8jo0%2BQTaO3ik7APllhYVzpMEBGOliRFwXuQeFNgrxbrWlu%2FR5gCnz%2F4reZl9mtPCj%2BA1YaBanxqP6f35ajfg7gSX%2FR40FSbPRfWlqkrAYW73kJMlW%2BQfQTN8uKAc2zGom8Myp7U%2BcSdvVGeYYd7YshoodgtO%2BnG8mmib8zzvpIjUN7bxpsjV9zpomP5SqITjDmcVjIkrXsCvrfIIV3B4LYD0i1IJCH24jxojodj2tAoUMCAV9YZldYvdnFJcMWML20WpAj7CMHlzkJE2kIwhAmvqZH2zwWmssnuMZnIxLwJWMUQyPq3aNFptBRFM7tO5YEeGe2dCc3dsDNd%2F5ynPTYh7DIGHDsXqnUdlA11dED%2FQYNtTWzRr%2BVVumWQEh7KE%2FKBaktz3B5JITdq52szkNrNC79SV3nJxDm4YGg1Uzhpvsm%2Frz%2BmpxIaZgtE1WwqEx9xescDzO0qNZSDDjdEdFH3V%2F1m9uKulemPI1cN1DQiMMe9sPRPYQoNaT2YXyl%2BKjlxe5okNpqNYMVU4oDERcONbJiQIpU5jjSa6ARLfC6lu3M9Qfp1C1BcV5fzds0wMaHsvUO3DAakLPayXwv4euWibhHVriaLNuftp9TTfGMsO3qYTDCa%2BNtAxdvF4ZHDTogKXwwTjZrkEVdBliTB%2BaH5EcvQ%2B4YD6Ft9WObiCI4Nn%2FhzaTvk2RcRg9HoIS%2Bn1czVsxhqk4jTHIIBy95siqZghF9edByZj5GTCw6dzMBjqZAVOKTWYXz0cZz9i35I2XreHckkyp5NgUoaJ2%2F2qIpm%2FieoBQf5jQVLOJXk2auSy94t%2BKgxMCtaSBPvPkH2RHuMpjAOzOT5yFZ2wVLQqg8NlzGqd3t1pD6FhiAUJAaYPCfYh0FM2vPNzFZGJEhyaV1kBJPqKUHvIjd0hRXpIxxsztBSQISF2t8Yize0ncRf7gCJ1edCwYm%2BjlIw%3D%3D&Expires=1771521931) - Architecture x8664 CPU op-modes 32-bit, 64-bit Address sizes 42 bits physical, 48 bits virtual Byte ...

3. [lspci_kv.txt](https://ppl-ai-file-upload.s3.amazonaws.com/web/direct-files/collection_05e0d332-5b67-43a5-8ccf-c47e1dc1a1e1/81705e02-b246-4201-8e1e-6fd32913625e/lspci_kv.txt?AWSAccessKeyId=ASIA2F3EMEYEUCKJPE7P&Signature=xSb5nqxmuXyO4vstfLBNhxCraaU%3D&x-amz-security-token=IQoJb3JpZ2luX2VjELn%2F%2F%2F%2F%2F%2F%2F%2F%2F%2FwEaCXVzLWVhc3QtMSJGMEQCIAHcs%2B3z61CmhRtndOHUTduizKIfkm%2FueSlagsj0ucgvAiBdMhT6WgNnJN7xDE4VtyeBX%2BK%2Bq%2FVje2eCNj4Tamipcir8BAiB%2F%2F%2F%2F%2F%2F%2F%2F%2F%2F8BEAEaDDY5OTc1MzMwOTcwNSIM%2Bhgt3IcpdHIXuWOIKtAEAgMqHHx%2Buo2ct0ilrTS%2B3jYvYvOwz8GFodHSHznQz%2Fi8uKcKkRR8jo0%2BQTaO3ik7APllhYVzpMEBGOliRFwXuQeFNgrxbrWlu%2FR5gCnz%2F4reZl9mtPCj%2BA1YaBanxqP6f35ajfg7gSX%2FR40FSbPRfWlqkrAYW73kJMlW%2BQfQTN8uKAc2zGom8Myp7U%2BcSdvVGeYYd7YshoodgtO%2BnG8mmib8zzvpIjUN7bxpsjV9zpomP5SqITjDmcVjIkrXsCvrfIIV3B4LYD0i1IJCH24jxojodj2tAoUMCAV9YZldYvdnFJcMWML20WpAj7CMHlzkJE2kIwhAmvqZH2zwWmssnuMZnIxLwJWMUQyPq3aNFptBRFM7tO5YEeGe2dCc3dsDNd%2F5ynPTYh7DIGHDsXqnUdlA11dED%2FQYNtTWzRr%2BVVumWQEh7KE%2FKBaktz3B5JITdq52szkNrNC79SV3nJxDm4YGg1Uzhpvsm%2Frz%2BmpxIaZgtE1WwqEx9xescDzO0qNZSDDjdEdFH3V%2F1m9uKulemPI1cN1DQiMMe9sPRPYQoNaT2YXyl%2BKjlxe5okNpqNYMVU4oDERcONbJiQIpU5jjSa6ARLfC6lu3M9Qfp1C1BcV5fzds0wMaHsvUO3DAakLPayXwv4euWibhHVriaLNuftp9TTfGMsO3qYTDCa%2BNtAxdvF4ZHDTogKXwwTjZrkEVdBliTB%2BaH5EcvQ%2B4YD6Ft9WObiCI4Nn%2FhzaTvk2RcRg9HoIS%2Bn1czVsxhqk4jTHIIBy95siqZghF9edByZj5GTCw6dzMBjqZAVOKTWYXz0cZz9i35I2XreHckkyp5NgUoaJ2%2F2qIpm%2FieoBQf5jQVLOJXk2auSy94t%2BKgxMCtaSBPvPkH2RHuMpjAOzOT5yFZ2wVLQqg8NlzGqd3t1pD6FhiAUJAaYPCfYh0FM2vPNzFZGJEhyaV1kBJPqKUHvIjd0hRXpIxxsztBSQISF2t8Yize0ncRf7gCJ1edCwYm%2BjlIw%3D%3D&Expires=1771521931) - 00:00.0 Host bridge: Intel Corporation Arrow Lake-H 6p+8e cores Host Bridge/DRAM Controller (rev 05)...

4. [lsmod.txt](https://ppl-ai-file-upload.s3.amazonaws.com/web/direct-files/collection_05e0d332-5b67-43a5-8ccf-c47e1dc1a1e1/7e5ca69b-7e44-45d7-9bec-cd18b4627abf/lsmod.txt?AWSAccessKeyId=ASIA2F3EMEYEUCKJPE7P&Signature=TWdOMHoExjmgsC1Arhrthx0jCPk%3D&x-amz-security-token=IQoJb3JpZ2luX2VjELn%2F%2F%2F%2F%2F%2F%2F%2F%2F%2FwEaCXVzLWVhc3QtMSJGMEQCIAHcs%2B3z61CmhRtndOHUTduizKIfkm%2FueSlagsj0ucgvAiBdMhT6WgNnJN7xDE4VtyeBX%2BK%2Bq%2FVje2eCNj4Tamipcir8BAiB%2F%2F%2F%2F%2F%2F%2F%2F%2F%2F8BEAEaDDY5OTc1MzMwOTcwNSIM%2Bhgt3IcpdHIXuWOIKtAEAgMqHHx%2Buo2ct0ilrTS%2B3jYvYvOwz8GFodHSHznQz%2Fi8uKcKkRR8jo0%2BQTaO3ik7APllhYVzpMEBGOliRFwXuQeFNgrxbrWlu%2FR5gCnz%2F4reZl9mtPCj%2BA1YaBanxqP6f35ajfg7gSX%2FR40FSbPRfWlqkrAYW73kJMlW%2BQfQTN8uKAc2zGom8Myp7U%2BcSdvVGeYYd7YshoodgtO%2BnG8mmib8zzvpIjUN7bxpsjV9zpomP5SqITjDmcVjIkrXsCvrfIIV3B4LYD0i1IJCH24jxojodj2tAoUMCAV9YZldYvdnFJcMWML20WpAj7CMHlzkJE2kIwhAmvqZH2zwWmssnuMZnIxLwJWMUQyPq3aNFptBRFM7tO5YEeGe2dCc3dsDNd%2F5ynPTYh7DIGHDsXqnUdlA11dED%2FQYNtTWzRr%2BVVumWQEh7KE%2FKBaktz3B5JITdq52szkNrNC79SV3nJxDm4YGg1Uzhpvsm%2Frz%2BmpxIaZgtE1WwqEx9xescDzO0qNZSDDjdEdFH3V%2F1m9uKulemPI1cN1DQiMMe9sPRPYQoNaT2YXyl%2BKjlxe5okNpqNYMVU4oDERcONbJiQIpU5jjSa6ARLfC6lu3M9Qfp1C1BcV5fzds0wMaHsvUO3DAakLPayXwv4euWibhHVriaLNuftp9TTfGMsO3qYTDCa%2BNtAxdvF4ZHDTogKXwwTjZrkEVdBliTB%2BaH5EcvQ%2B4YD6Ft9WObiCI4Nn%2FhzaTvk2RcRg9HoIS%2Bn1czVsxhqk4jTHIIBy95siqZghF9edByZj5GTCw6dzMBjqZAVOKTWYXz0cZz9i35I2XreHckkyp5NgUoaJ2%2F2qIpm%2FieoBQf5jQVLOJXk2auSy94t%2BKgxMCtaSBPvPkH2RHuMpjAOzOT5yFZ2wVLQqg8NlzGqd3t1pD6FhiAUJAaYPCfYh0FM2vPNzFZGJEhyaV1kBJPqKUHvIjd0hRXpIxxsztBSQISF2t8Yize0ncRf7gCJ1edCwYm%2BjlIw%3D%3D&Expires=1771521931) - Module                  Size  Used by
snd_hda_codec_intelhdmi    28672  1
xe                   43827...

5. [dmesg-full.txt](https://ppl-ai-file-upload.s3.amazonaws.com/web/direct-files/collection_05e0d332-5b67-43a5-8ccf-c47e1dc1a1e1/2d6c4578-7900-4cf2-b2b9-5c63326d01a2/dmesg-full.txt?AWSAccessKeyId=ASIA2F3EMEYEUCKJPE7P&Signature=NjpO5ydOTyr2cjyIf%2BaDAKZBmfE%3D&x-amz-security-token=IQoJb3JpZ2luX2VjELn%2F%2F%2F%2F%2F%2F%2F%2F%2F%2FwEaCXVzLWVhc3QtMSJGMEQCIAHcs%2B3z61CmhRtndOHUTduizKIfkm%2FueSlagsj0ucgvAiBdMhT6WgNnJN7xDE4VtyeBX%2BK%2Bq%2FVje2eCNj4Tamipcir8BAiB%2F%2F%2F%2F%2F%2F%2F%2F%2F%2F8BEAEaDDY5OTc1MzMwOTcwNSIM%2Bhgt3IcpdHIXuWOIKtAEAgMqHHx%2Buo2ct0ilrTS%2B3jYvYvOwz8GFodHSHznQz%2Fi8uKcKkRR8jo0%2BQTaO3ik7APllhYVzpMEBGOliRFwXuQeFNgrxbrWlu%2FR5gCnz%2F4reZl9mtPCj%2BA1YaBanxqP6f35ajfg7gSX%2FR40FSbPRfWlqkrAYW73kJMlW%2BQfQTN8uKAc2zGom8Myp7U%2BcSdvVGeYYd7YshoodgtO%2BnG8mmib8zzvpIjUN7bxpsjV9zpomP5SqITjDmcVjIkrXsCvrfIIV3B4LYD0i1IJCH24jxojodj2tAoUMCAV9YZldYvdnFJcMWML20WpAj7CMHlzkJE2kIwhAmvqZH2zwWmssnuMZnIxLwJWMUQyPq3aNFptBRFM7tO5YEeGe2dCc3dsDNd%2F5ynPTYh7DIGHDsXqnUdlA11dED%2FQYNtTWzRr%2BVVumWQEh7KE%2FKBaktz3B5JITdq52szkNrNC79SV3nJxDm4YGg1Uzhpvsm%2Frz%2BmpxIaZgtE1WwqEx9xescDzO0qNZSDDjdEdFH3V%2F1m9uKulemPI1cN1DQiMMe9sPRPYQoNaT2YXyl%2BKjlxe5okNpqNYMVU4oDERcONbJiQIpU5jjSa6ARLfC6lu3M9Qfp1C1BcV5fzds0wMaHsvUO3DAakLPayXwv4euWibhHVriaLNuftp9TTfGMsO3qYTDCa%2BNtAxdvF4ZHDTogKXwwTjZrkEVdBliTB%2BaH5EcvQ%2B4YD6Ft9WObiCI4Nn%2FhzaTvk2RcRg9HoIS%2Bn1czVsxhqk4jTHIIBy95siqZghF9edByZj5GTCw6dzMBjqZAVOKTWYXz0cZz9i35I2XreHckkyp5NgUoaJ2%2F2qIpm%2FieoBQf5jQVLOJXk2auSy94t%2BKgxMCtaSBPvPkH2RHuMpjAOzOT5yFZ2wVLQqg8NlzGqd3t1pD6FhiAUJAaYPCfYh0FM2vPNzFZGJEhyaV1kBJPqKUHvIjd0hRXpIxxsztBSQISF2t8Yize0ncRf7gCJ1edCwYm%2BjlIw%3D%3D&Expires=1771521931) - 0.000000 Linux version 6.18.8-gentoo-lopez rootstartop gcc Gentoo 15.2.1p20251122 p3 15.2.1 20251122...

6. [lsblk-detail.txt](https://ppl-ai-file-upload.s3.amazonaws.com/web/direct-files/collection_05e0d332-5b67-43a5-8ccf-c47e1dc1a1e1/7a744206-5adc-4eb0-9591-70d1894c914a/lsblk-detail.txt?AWSAccessKeyId=ASIA2F3EMEYEUCKJPE7P&Signature=aMpQmtn5Rqzn8Bqyps1jbLLPwKY%3D&x-amz-security-token=IQoJb3JpZ2luX2VjELn%2F%2F%2F%2F%2F%2F%2F%2F%2F%2FwEaCXVzLWVhc3QtMSJGMEQCIAHcs%2B3z61CmhRtndOHUTduizKIfkm%2FueSlagsj0ucgvAiBdMhT6WgNnJN7xDE4VtyeBX%2BK%2Bq%2FVje2eCNj4Tamipcir8BAiB%2F%2F%2F%2F%2F%2F%2F%2F%2F%2F8BEAEaDDY5OTc1MzMwOTcwNSIM%2Bhgt3IcpdHIXuWOIKtAEAgMqHHx%2Buo2ct0ilrTS%2B3jYvYvOwz8GFodHSHznQz%2Fi8uKcKkRR8jo0%2BQTaO3ik7APllhYVzpMEBGOliRFwXuQeFNgrxbrWlu%2FR5gCnz%2F4reZl9mtPCj%2BA1YaBanxqP6f35ajfg7gSX%2FR40FSbPRfWlqkrAYW73kJMlW%2BQfQTN8uKAc2zGom8Myp7U%2BcSdvVGeYYd7YshoodgtO%2BnG8mmib8zzvpIjUN7bxpsjV9zpomP5SqITjDmcVjIkrXsCvrfIIV3B4LYD0i1IJCH24jxojodj2tAoUMCAV9YZldYvdnFJcMWML20WpAj7CMHlzkJE2kIwhAmvqZH2zwWmssnuMZnIxLwJWMUQyPq3aNFptBRFM7tO5YEeGe2dCc3dsDNd%2F5ynPTYh7DIGHDsXqnUdlA11dED%2FQYNtTWzRr%2BVVumWQEh7KE%2FKBaktz3B5JITdq52szkNrNC79SV3nJxDm4YGg1Uzhpvsm%2Frz%2BmpxIaZgtE1WwqEx9xescDzO0qNZSDDjdEdFH3V%2F1m9uKulemPI1cN1DQiMMe9sPRPYQoNaT2YXyl%2BKjlxe5okNpqNYMVU4oDERcONbJiQIpU5jjSa6ARLfC6lu3M9Qfp1C1BcV5fzds0wMaHsvUO3DAakLPayXwv4euWibhHVriaLNuftp9TTfGMsO3qYTDCa%2BNtAxdvF4ZHDTogKXwwTjZrkEVdBliTB%2BaH5EcvQ%2B4YD6Ft9WObiCI4Nn%2FhzaTvk2RcRg9HoIS%2Bn1czVsxhqk4jTHIIBy95siqZghF9edByZj5GTCw6dzMBjqZAVOKTWYXz0cZz9i35I2XreHckkyp5NgUoaJ2%2F2qIpm%2FieoBQf5jQVLOJXk2auSy94t%2BKgxMCtaSBPvPkH2RHuMpjAOzOT5yFZ2wVLQqg8NlzGqd3t1pD6FhiAUJAaYPCfYh0FM2vPNzFZGJEhyaV1kBJPqKUHvIjd0hRXpIxxsztBSQISF2t8Yize0ncRf7gCJ1edCwYm%2BjlIw%3D%3D&Expires=1771521931) - NAME MODEL SIZE ROTA DISC-GRAN DISC-MAX WSAME nvme0n1 Samsung SSD 990PRO 1TB 953.9G 0 512B 2T 0B nvm...

7. [power-sleep-states.txt](https://ppl-ai-file-upload.s3.amazonaws.com/web/direct-files/collection_05e0d332-5b67-43a5-8ccf-c47e1dc1a1e1/262a783b-8e7a-425d-b288-9541adc9ee53/power-sleep-states.txt?AWSAccessKeyId=ASIA2F3EMEYEUCKJPE7P&Signature=WfiX75lmaZOIO5aNGYoxhtKNbk8%3D&x-amz-security-token=IQoJb3JpZ2luX2VjELn%2F%2F%2F%2F%2F%2F%2F%2F%2F%2FwEaCXVzLWVhc3QtMSJGMEQCIAHcs%2B3z61CmhRtndOHUTduizKIfkm%2FueSlagsj0ucgvAiBdMhT6WgNnJN7xDE4VtyeBX%2BK%2Bq%2FVje2eCNj4Tamipcir8BAiB%2F%2F%2F%2F%2F%2F%2F%2F%2F%2F8BEAEaDDY5OTc1MzMwOTcwNSIM%2Bhgt3IcpdHIXuWOIKtAEAgMqHHx%2Buo2ct0ilrTS%2B3jYvYvOwz8GFodHSHznQz%2Fi8uKcKkRR8jo0%2BQTaO3ik7APllhYVzpMEBGOliRFwXuQeFNgrxbrWlu%2FR5gCnz%2F4reZl9mtPCj%2BA1YaBanxqP6f35ajfg7gSX%2FR40FSbPRfWlqkrAYW73kJMlW%2BQfQTN8uKAc2zGom8Myp7U%2BcSdvVGeYYd7YshoodgtO%2BnG8mmib8zzvpIjUN7bxpsjV9zpomP5SqITjDmcVjIkrXsCvrfIIV3B4LYD0i1IJCH24jxojodj2tAoUMCAV9YZldYvdnFJcMWML20WpAj7CMHlzkJE2kIwhAmvqZH2zwWmssnuMZnIxLwJWMUQyPq3aNFptBRFM7tO5YEeGe2dCc3dsDNd%2F5ynPTYh7DIGHDsXqnUdlA11dED%2FQYNtTWzRr%2BVVumWQEh7KE%2FKBaktz3B5JITdq52szkNrNC79SV3nJxDm4YGg1Uzhpvsm%2Frz%2BmpxIaZgtE1WwqEx9xescDzO0qNZSDDjdEdFH3V%2F1m9uKulemPI1cN1DQiMMe9sPRPYQoNaT2YXyl%2BKjlxe5okNpqNYMVU4oDERcONbJiQIpU5jjSa6ARLfC6lu3M9Qfp1C1BcV5fzds0wMaHsvUO3DAakLPayXwv4euWibhHVriaLNuftp9TTfGMsO3qYTDCa%2BNtAxdvF4ZHDTogKXwwTjZrkEVdBliTB%2BaH5EcvQ%2B4YD6Ft9WObiCI4Nn%2FhzaTvk2RcRg9HoIS%2Bn1czVsxhqk4jTHIIBy95siqZghF9edByZj5GTCw6dzMBjqZAVOKTWYXz0cZz9i35I2XreHckkyp5NgUoaJ2%2F2qIpm%2FieoBQf5jQVLOJXk2auSy94t%2BKgxMCtaSBPvPkH2RHuMpjAOzOT5yFZ2wVLQqg8NlzGqd3t1pD6FhiAUJAaYPCfYh0FM2vPNzFZGJEhyaV1kBJPqKUHvIjd0hRXpIxxsztBSQISF2t8Yize0ncRf7gCJ1edCwYm%2BjlIw%3D%3D&Expires=1771521931) - freeze mem disk TITLE syspowerstate

8. [kernel-config-6.18.8-full.txt](https://ppl-ai-file-upload.s3.amazonaws.com/web/direct-files/collection_05e0d332-5b67-43a5-8ccf-c47e1dc1a1e1/ff0b786c-db31-42a8-bef8-b70b53ac19c9/kernel-config-6.18.8-full.txt?AWSAccessKeyId=ASIA2F3EMEYEUCKJPE7P&Signature=m9ceBtX5y%2Fd5vWi%2FDAaTTc2CrQg%3D&x-amz-security-token=IQoJb3JpZ2luX2VjELn%2F%2F%2F%2F%2F%2F%2F%2F%2F%2FwEaCXVzLWVhc3QtMSJGMEQCIAHcs%2B3z61CmhRtndOHUTduizKIfkm%2FueSlagsj0ucgvAiBdMhT6WgNnJN7xDE4VtyeBX%2BK%2Bq%2FVje2eCNj4Tamipcir8BAiB%2F%2F%2F%2F%2F%2F%2F%2F%2F%2F8BEAEaDDY5OTc1MzMwOTcwNSIM%2Bhgt3IcpdHIXuWOIKtAEAgMqHHx%2Buo2ct0ilrTS%2B3jYvYvOwz8GFodHSHznQz%2Fi8uKcKkRR8jo0%2BQTaO3ik7APllhYVzpMEBGOliRFwXuQeFNgrxbrWlu%2FR5gCnz%2F4reZl9mtPCj%2BA1YaBanxqP6f35ajfg7gSX%2FR40FSbPRfWlqkrAYW73kJMlW%2BQfQTN8uKAc2zGom8Myp7U%2BcSdvVGeYYd7YshoodgtO%2BnG8mmib8zzvpIjUN7bxpsjV9zpomP5SqITjDmcVjIkrXsCvrfIIV3B4LYD0i1IJCH24jxojodj2tAoUMCAV9YZldYvdnFJcMWML20WpAj7CMHlzkJE2kIwhAmvqZH2zwWmssnuMZnIxLwJWMUQyPq3aNFptBRFM7tO5YEeGe2dCc3dsDNd%2F5ynPTYh7DIGHDsXqnUdlA11dED%2FQYNtTWzRr%2BVVumWQEh7KE%2FKBaktz3B5JITdq52szkNrNC79SV3nJxDm4YGg1Uzhpvsm%2Frz%2BmpxIaZgtE1WwqEx9xescDzO0qNZSDDjdEdFH3V%2F1m9uKulemPI1cN1DQiMMe9sPRPYQoNaT2YXyl%2BKjlxe5okNpqNYMVU4oDERcONbJiQIpU5jjSa6ARLfC6lu3M9Qfp1C1BcV5fzds0wMaHsvUO3DAakLPayXwv4euWibhHVriaLNuftp9TTfGMsO3qYTDCa%2BNtAxdvF4ZHDTogKXwwTjZrkEVdBliTB%2BaH5EcvQ%2B4YD6Ft9WObiCI4Nn%2FhzaTvk2RcRg9HoIS%2Bn1czVsxhqk4jTHIIBy95siqZghF9edByZj5GTCw6dzMBjqZAVOKTWYXz0cZz9i35I2XreHckkyp5NgUoaJ2%2F2qIpm%2FieoBQf5jQVLOJXk2auSy94t%2BKgxMCtaSBPvPkH2RHuMpjAOzOT5yFZ2wVLQqg8NlzGqd3t1pD6FhiAUJAaYPCfYh0FM2vPNzFZGJEhyaV1kBJPqKUHvIjd0hRXpIxxsztBSQISF2t8Yize0ncRf7gCJ1edCwYm%2BjlIw%3D%3D&Expires=1771521931) - CONFIGX86SGXy CONFIGX86USERSHADOWSTACKy CONFIGINTELTDXHOSTy CONFIGEFIy CONFIGEFISTUBy CONFIGEFIHANDO...

## Addendum: Speeding Up Kernel Builds and Linking

The following changes and practices reduce build and especially link time while keeping the plan’s goals intact.
A. Use all 16 cores

    Change your build command:

    bash
    KCFLAGS="-march=native -O2 -pipe" make -j16

    Reason: The CPU has 16 hardware threads and no SMT; -j16 uses the whole chip instead of the current -j12.

B. Trim debug and tracing to shrink vmlinux

Tracers (keep basic ftrace only)

    Path: Kernel hacking → Tracers

    Set:

        Keep:

            CONFIG_FTRACE=y
            CONFIG_EVENT_TRACING=y

        Disable:

            # CONFIG_FUNCTION_TRACER is not set
            # CONFIG_FUNCTION_GRAPH_TRACER is not set
            # CONFIG_SCHED_TRACER is not set
            # CONFIG_HWLAT_TRACER is not set
            # CONFIG_OSNOISE_TRACER is not set
            # CONFIG_TIMERLAT_TRACER is not set
            # CONFIG_MMIOTRACE is not set
            # CONFIG_BLK_DEV_IO_TRACE is not set
            # CONFIG_STACK_TRACER is not set
            # CONFIG_FUNCTION_PROFILER is not set​

    Reason: These tracers add large amounts of instrumentation and debug sections, inflating link work and kernel size.​

Disable KFENCE

    Path: Kernel hacking → Memory Debugging → KFENCE

    Set:

        # CONFIG_KFENCE is not set​

    Reason: KFENCE reserves memory and adds guard logic; useful for debugging, unnecessary for production and slows builds.​

Disable UBSAN if present

    Path: Kernel hacking → Generic Kernel Debugging Instruments → Undefined behaviour sanitizer

    Set:

        # CONFIG_UBSAN is not set​

    Reason: UBSAN injects many checks into code, increasing compilation and link time.​

Disable PM/ACPI debug where not needed

    Path: Power management and ACPI options → Power management debug

    Set:

        # CONFIG_PM_DEBUG is not set
        # CONFIG_PM_TEST_SUSPEND is not set
        # CONFIG_PM_SLEEP_DEBUG is not set
        # CONFIG_PM_TRACE is not set
        # CONFIG_PM_TRACE_RTC is not set​

    Reason: These options add extra debug code for suspend/resume diagnostics; not needed in normal use.​

C. Avoid heavy sanitizers and extra profiling

KASAN/KMSAN/KCSAN

    Path: Kernel hacking → Memory Debugging

    Ensure:

        # CONFIG_KASAN is not set
        # CONFIG_KMSAN is not set
        # CONFIG_KCSAN is not set​

    Reason: Sanitizers are extremely expensive in build time and binary size.

Profiling support

    Path: General setup → Profiling support

    Optionally:

        # CONFIG_PROFILING is not set​

    Reason: Old-style profiling adds some extra objects; perf will still work via perf events.​

D. Turn off BTF if not needed for BPF CO-RE

    Path: Kernel hacking → Compile-time checks and compiler options → Debug information

    Set:

        # CONFIG_DEBUG_INFO_BTF is not set
        # CONFIG_DEBUG_INFO_BTF_MODULES is not set​

    Reason: BTF generation and embedding is link-intensive; skip if you are not using CO-RE BPF tools.​

E. Keep LTO disabled

    Path: Kernel hacking → Link Time Optimization (LTO)

    Ensure:

        CONFIG_LTO_NONE=y
        # CONFIG_LTO_CLANG_FULL is not set
        # CONFIG_LTO_CLANG_THIN is not set​

    Reason: LTO is very slow for large kernels; you already have it off, keep it that way.​

F. Shrink the kernel to shrink link time

    Earlier phases (removing Xen/Hyper-V/TDX guest code, unused filesystems, SCSI/ATA, staging drivers, unused LSMs, SOF audio, xe, etc.) will significantly reduce the amount of code and debug data the linker has to handle.

    Reason: Less code compiled and linked directly translates into faster builds and smaller vmlinux.

G. Use ccache for repeated rebuilds

    Install:

    bash
    emerge --ask dev-util/ccache

    For kernel builds:

    bash
    export CC="ccache gcc"
    KCFLAGS="-march=native -O2 -pipe" make -j16

    Reason: ccache avoids recompiling unchanged translation units between incremental kernel tweaks; the final link still runs but the compile phase shrinks noticeably.

H. Build from a stable defconfig, not localmodconfig each time

    Workflow:

        Maintain /root/defconfig-starfighter with make savedefconfig.

        For each rebuild:

        bash
        cp /root/defconfig-starfighter .config
        make olddefconfig

    Only rerun make localmodconfig when jumping to a new kernel generation, then regenerate the defconfig.

    Reason: localmodconfig itself takes time and tends to churn options, causing unnecessary recompiles compared to a stable defconfig baseline.​
