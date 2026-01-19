
# PROJECT.md - Linux boot optimization

## Repo overview
- PROJECT.md (this file): human-facing overview
- AGENTS.md
- PLAN-*.md:
- docs/*.md: finished howto documentaion on completed tasks
- notes/*: scratch notes while working on tasks (deleted on completion)

## Big Objectives
- minimal: customized linux kernel, initrd, firmware, userspace boot
- speed: optimized boot including kernel and user space
- security: full luks encryption with multiple decrypt, secure boot, TPM

## Roadmap
- [ ] boot without external bootloader using EFI stub
- [ ] embed initrd and kernel arguments into UKI
- [ ] customize a minimized kernel for fast build times
    - [ ] understand where to get all boot related logs/info
    - [ ] minimal pieces built as modules; document when required
- [ ] remove unneeded firmware
- [ ] replace genkernel with ugrd
- [ ] custom initrd from scratch
- [ ] enable secure boot
- [ ] streamline kernel upgrade process
- [ ] decrypt with hardware token (usb drive, yubikey) with passphrase fallback
- [ ] 2FA decrypt with hardware token + passphrase
- [ ] eyecandy luks decrypt prompt

## Plan index
