#!/bin/bash

# CPU topology and features
lscpu > lscpu.txt

# CPU frequency driver
{
  echo "## scaling_driver"
  cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver 2>/dev/null || echo "no scaling_driver"
  echo
  echo "## Available policies"
  for p in /sys/devices/system/cpu/cpufreq/policy*; do
    [ -d "$p" ] || continue
    echo "== $p =="
    cat "$p/scaling_governor" 2>/dev/null || true
    cat "$p/energy_performance_preference" 2>/dev/null || true
  done
} > cpu-freq-and-epp.txt

# intel_pstate presence
{
  echo "## /sys/devices/system/cpu/intel_pstate contents"
  if [ -d /sys/devices/system/cpu/intel_pstate ]; then
    ls -l /sys/devices/system/cpu/intel_pstate
    echo
    grep . /sys/devices/system/cpu/intel_pstate/* 2>/dev/null || true
  else
    echo "intel_pstate directory not present"
  fi
} > intel_pstate-sysfs.txt

# sensors (requires lm_sensors configured)
sensors > sensors.txt 2>&1 || echo "sensors failed" > sensors.txt
