# Gentoo configuration layout

This repository is designed to be checked out with `/` as its Git work tree on
every managed host. Files at their normal system paths are therefore both live
configuration and ordinary tracked files; there is no separate deployment or
synchronization step.

Universal policy belongs in native common fragments. Host-specific policy
belongs in a native fragment named for the host and is selected through
`/etc/gentoo-config/target-host`. Do not copy a complete common file into a host
variant, and do not make a common file silently depend on the machine where it
was edited.

Prefer native fragment, include, matching, and drop-in mechanisms. If a future
configuration format cannot express a common layer plus a selected host layer,
document that limitation before introducing generation, copying, or symlinks.

The supported initial host names are `generic`, `qemu`, and `thinktop`.
`target-host` is intentionally local state rather than a tracked file because
its value differs between installations. It contains the Portage-compatible
assignment `GENTOO_TARGET_HOST="name"` so `make.conf` can source it directly.

Kernel firmware requirements use shell assignment fragments under
`/etc/gentoo-config/kernel-firmware.d/`: the installer reads `00-common` first,
then `90-${GENTOO_TARGET_HOST}` when present. `SOF_FIRMWARE` must be `yes` or
`no`; the common default is `no`, and `thinktop` enables it for its audio DSP.
These files describe the target hardware, independent of the installation host.
