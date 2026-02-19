
# Bootloader Delete - EFI stub boot

The linux kernel can boot directly from (U)EFI firmware by emulating a (FIXME: PK?) binary and being placed in an agreed-upon place where the firmware can find it.

## linux kernel configuration

## EFI firmware configuration

Sometimes it is preferable to maintain multiple bootable options, and maintaining the list of firmmware boot options fromm userspace makes this convenient.

efibootmgr, lsblk, blkid, etc.
