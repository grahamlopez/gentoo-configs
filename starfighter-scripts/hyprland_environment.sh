#!/bin/bash


# Hyprland config (adjust path if needed)
if [ -f ~/.config/hypr/hyprland.conf ]; then
  cp ~/.config/hypr/hyprland.conf hyprland.conf.txt
fi

# Environment.d configs
if [ -d ~/.config/environment.d ]; then
  tar czf environment.d.tar.gz -C ~/.config environment.d
fi
