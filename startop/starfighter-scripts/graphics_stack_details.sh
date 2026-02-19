#!/bin/bash

# DRM / Intel GPU messages from dmesg and journal
sudo dmesg | grep -iE 'drm|i915|xe ' > dmesg-drm.txt
sudo journalctl -b | grep -iE 'drm|i915|xe ' > journal-drm.txt

# OpenGL info (glxinfo -B)
glxinfo -B > glxinfo-B.txt 2>&1 || echo "glxinfo not available" > glxinfo-B.txt

# Vulkan summary
vulkaninfo --summary > vulkaninfo-summary.txt 2>&1 || echo "vulkaninfo not available" > vulkaninfo-summary.txt

# Relevant kernel config bits (from /proc/config.gz if enabled)
if zgrep -q . /proc/config.gz 2>/dev/null; then
  {
    echo "## DRM / Intel / power config"
    zgrep -E 'CONFIG_DRM_XE|CONFIG_DRM_I915|CONFIG_INTEL_PMC|CONFIG_CPU_IDLE' /proc/config.gz || true
  } > kernel-config-gfx-power.txt
else
  echo "/proc/config.gz not available; please later send relevant .config snippets" > kernel-config-gfx-power.txt
fi
