#!/bin/bash

# Current kernel cmdline
cat /proc/cmdline > kernel-cmdline.txt

# If you have a script or command sequence you use to install the EFI stub kernel,
# copy it here manually or paste into a file:
cat > notes-kernel-install.txt << 'EOF'
Describe (or paste) how you build and install your EFI stub kernel here.
For example:
- make commands
- genkernel/dracut/dracut-systemd steps (if any)
- how you copy the kernel to the EFI partition
- whether you use an initramfs (and which generator)
EOF
