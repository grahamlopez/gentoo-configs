#!/bin/bash

sudo sh -c '
# Block devices overview
lsblk -o NAME,MODEL,SIZE,ROTA,DISC-GRAN,DISC-MAX,WSAME > lsblk-detail.txt

# NVMe list
nvme list > nvme-list.txt 2>&1 || echo "nvme command not available" > nvme-list.txt

# NVMe controller + power state feature for each nvmeX
{
  for dev in /dev/nvme[0-9]; do
    [ -e "$dev" ] || continue
    echo "===== $dev: id-ctrl ====="
    nvme id-ctrl "$dev" 2>&1 || echo "id-ctrl failed for $dev"
    echo
    echo "===== $dev: feature 2 (power mgmt) ====="
    nvme get-feature "$dev" -f 2 -H 2>&1 || echo "get-feature -f 2 failed for $dev"
    echo
  done
} > nvme-controllers-and-power.txt 2>&1

# I/O scheduler and add_random
{
  for b in /sys/block/nvme*; do
    [ -d "$b" ] || continue
    dev=$(basename "$b")
    echo "===== $dev ====="
    echo -n "scheduler: "
    cat "$b/queue/scheduler" 2>/dev/null || echo "no scheduler file"
    echo -n "add_random: "
    cat "$b/queue/add_random" 2>/dev/null || echo "no add_random file"
    echo
  done
} > nvme-queue-settings.txt
'
