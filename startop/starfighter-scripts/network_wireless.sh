#!/bin/bash

sudo sh -c '
# NetworkManager devices
nmcli device show > nmcli-device-show.txt 2>&1 || echo "nmcli not available" > nmcli-device-show.txt

# Basic iw info (phy0 may differ; we capture all)
{
  for phy in /sys/class/ieee80211/*; do
    [ -d "$phy" ] || continue
    phyname=$(basename "$phy")
    echo "===== $phyname: iw phy info ====="
    iw "$phyname" info 2>&1 || echo "iw info failed for $phyname"
    echo
  done
} > iw-phy-info.txt 2>&1

# Per-interface link and power_save status (for all wlan* devices)
{
  for ifc in $(ls /sys/class/net 2>/dev/null | grep -E '^wlan|^wl'); do
    echo "===== $ifc ====="
    iw dev "$ifc" link 2>&1 || echo "iw link failed for $ifc"
    echo
    iw dev "$ifc" get power_save 2>&1 || echo "iw get power_save failed for $ifc"
    echo
  done
} > wifi-link-and-powersave.txt 2>&1

# WiFi-related journal excerpts
journalctl -b | grep -iE 'iwlwifi|ax210|wifi|wlan' > journal-wifi.txt
'
