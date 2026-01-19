
# Unified kernel image (UKI)

The kernel image can embed the initrd and its commandline arguments so that the
binary itself is all that is required to boot; the firmware doesn't have to be
told where the initrd is located or any extra parameters to pass to the kernel.
