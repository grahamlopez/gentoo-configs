#!/bin/bash

sudo sh -c '
# DMI / firmware info
{
  echo "## DMI / Firmware"
  grep . /sys/class/dmi/id/{sys_vendor,product_name,product_version,bios_*} 2>/dev/null
} > dmi-info.txt

# dmesg from current boot (unfiltered)
dmesg > dmesg-full.txt

# Kernel modules and modprobe config
lsmod > lsmod.txt
modprobe -c > modprobe.conf.txt

# Supported sleep states
{
  echo "## /sys/power/state"
  cat /sys/power/state 2>/dev/null || echo "no /sys/power/state"
  echo
  echo "## /sys/power/mem_sleep"
  cat /sys/power/mem_sleep 2>/dev/null || echo "no /sys/power/mem_sleep"
} > power-sleep-states.txt

# systemd-logind info
journalctl -b -u systemd-logind > journal-logind.txt

# ACPI / thermal / suspend related log excerpts
journalctl -b | grep -iE 'suspend|resume|acpi|thermal' > journal-power-thermal.txt
'
