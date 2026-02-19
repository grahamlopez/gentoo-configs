#!/bin/bash

# upower dump
upower -d > upower-dump.txt 2>&1 || echo "upower not available" > upower-dump.txt

# Raw battery uevent
{
  for b in /sys/class/power_supply/BAT*; do
    [ -d "$b" ] || continue
    echo "===== $b ====="
    cat "$b/uevent"
    echo
  done
} > battery-uevent.txt 2>&1

# 10-second, non-interactive HTML + CSV snapshot
sudo powertop --time=10 --iteration=1 --html=powertop.html --csv=powertop.csv

# After running the powertop line, let it sit for a bit on battery at an idle Hyprland desktop so the HTML reflects realistic idle usage.
# 
# If you can, also note manually (in a text file) what you observe:
# 
cat > notes-user-observations.txt << 'EOF'
Idle power on battery (from powertop or upower): ...
Approximate battery life under typical workload: ...
Anything odd you notice (fans, heat, glitches): ...
EOF

# Edit that file with your observations.
