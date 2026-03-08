#!/bin/sh

# A safer subset than the powertop --autotune

# USB autosuspend for non-critical devices
for dev in /sys/bus/usb/devices/*/power/control; do
  [ -f "$dev" ] || continue
  echo auto > "$dev" 2>/dev/null || true
done

# Runtime PM for PCI devices
for dev in /sys/bus/pci/devices/*/power/control; do
  [ -f "$dev" ] || continue
  # Leave GPUs and root ports alone for now
  case "$dev" in
    *0000:00:02.0/power/control)  # iGPU on your box
      continue
      ;;
  esac
  echo auto > "$dev" 2>/dev/null || true
done

# Enable autosuspend for Bluetooth and other HID where possible
for f in /sys/bus/usb/devices/*/power/autosuspend; do
  [ -f "$f" ] || continue
  echo 2 > "$f" 2>/dev/null || true
done

# Audio power saving (HDA)
if [ -f /sys/module/snd_hda_intel/parameters/power_save ]; then
  echo 1  > /sys/module/snd_hda_intel/parameters/power_save 2>/dev/null || true
fi
if [ -f /sys/module/snd_hda_intel/parameters/power_save_controller ]; then
  echo Y  > /sys/module/snd_hda_intel/parameters/power_save_controller 2>/dev/null || true
fi

# SATA / AHCI (if any; mostly for docking or external bays)
for host in /sys/class/scsi_host/host*/link_power_management_policy; do
  [ -f "$host" ] || continue
  echo med_power_with_dipm > "$host" 2>/dev/null || true
done
