#!/bin/bash


#To see the current state of things, especially how it relates to boot process and times:

# systemd-analyze
# systemd-analyze blame
# systemd-analyze critical-chain

# Now disable some of the most obvious stuff

systemctl mask remote-cryptsetup.target
systemctl mask remote-fs.target
systemctl mask remote-integritysetup.target
systemctl mask remote-veritysetup.target
systemctl disable systemd-networkd-wait-online.service
systemctl disable systemd-networkd.service
systemctl disable systemd-network-generator.service
systemctl disable systemd-networkd-persistent-storage.service
systemctl disable systemd-networkd.socket
systemctl disable systemd-networkd-varlink.socket
systemctl disable systemd-nsresourced.service
systemctl disable systemd-nsresourced.socket

# Some potentially helpful things to disable, but might want to look into use in the future?

systemctl disable systemd-pstore.service
systemctl disable systemd-sysext.service
systemctl disable systemd-confext.service

# Even with dhcpcd+wpa_supplicant (no systemd-networkd), systemd-resolved is helpful for VPN, split DNS, and DNS-over-TLS setups. If none of those apply:

# systemctl disable systemd-resolved.service
# systemctl disable systemd-resolved-varlink.socket
# systemctl disable systemd-resolved-monitor.socket

# Could always disable NTP if you aren't worried about clock drift or DST

# systemctl disable systemd-timesyncd.service
