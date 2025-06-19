Thes are my scratch notes from installing Gentoo + Hyprland as minimally as
possible and setting things up from scratch.

using

- default/linux/amd64/23.0/desktop/systemd (stable)
- pipewire+wireplumber (no pulseaudio)
- dhcpcd+wpa_supplicant (no networkmanager)

# Get to first boot

## prepare disks

- partition with fdisk
  - 1-2 GB type EFI System
  - remainder type Linux filesystem
- set up encryption
  - cryptsetup luksFormat
- make and mount filesystems
  - vfat for boot, ext4 for /dev/mapper/root

## install base system

- install stage3 tarball
  - download desktop-systemd variant
  - `tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner -C /mnt/gentoo`
- configure make.conf, package.uses
- chroot
  - copy DNS info
  - mount/bind filesystems
- sync portage
- set the profile (desktop/systemd)
- set the timezone (defer if dual booting)
- configure locales
  - locale.gen
  - eselect

## install firmware and kernel

- emerge linux-firmware, gentoo-kernel
  - savedconfig
- `genkernel --luks initramfs`
- set up efibootmgr
  - `efibootmgr --create --index 5 --disk /dev/nvme0n1 --part 1 --label "gentoo-alt" --loader /EFI/boot/bootx64-alt.efi --unicode 'crypt_root=UUID=63fdec71-9236-43d1-8d4a-2f3afba7d59a root=UUID=f81baa5e-121b-4983-ab30-020d89fbe1f1 ro initrd=/EFI/boot/initrd-alt root_trim=yes'`
- re-emerge systemd with USE=cryptsetup

## final configuration

TODO:

- emerge utilities
- fstab
- systemd
- set up wireless networking

## boot into new install

- systemd-machine-id-setup
- systemd-firstboot --reset
- systemd-firstboot --prompt
- timedatectl set-local-rtc 1

# Install user environment

## set up user account

- `useradd -m -G users,wheel,audio,video,portage -s /usr/bin/zsh graham`
- probably later: `usermod -aG pipewire,locate graham`

## install compositor, terminal, browser

- blacklist nouveau in `/etc/modprobe.d/blacklist.conf`
-`echo auto > /sys/bus/pci/devices/0000\:01\:00.0/power/control`
- to automate, write
  ```
  w /sys/bus/pci/devices/0000:01:00.0/power/control - - - - auto
  ```
  to `/etc/tmpfiles.d/nvidia-power.conf`

## configure pcloud via rclone

- need a browser
- rclone config
- rclone mount pcloud: /home/graham/pcloud

## setup light/dark theme switching

- install xdg-desktop-portal-gtk xdg-desktop-portal-gtk
- reboot
- `gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'`
- set up keyd
  - `capslock = overload(control, esc)`

## streamline boot/login

- sudo for passwordless root: `visudo` and add `graham ALL=NOPASSWD: /bin/su -`
- terminal login: edit `/etc/systemd/system/getty.target.wants/getty@tty1.service` and add

  ```
  [Service]
  ExecStart=
  ExecStart=-/sbin/agetty --autologin <username> --noclear - ${TERM}
  ```

  then `systemctl daemon-reload` and `systemctl restart getty@tty1`

- automatic Hyprland start: edit `.zprofile` and add

  ```
  if [ "$(tty)" = "/dev/tty1" ]; then
      exec dbus-run-session Hyprland
  fi
  ```

## enable sound

- `systemctl --user enable --now pipewire.service pipewire-pulse.service wireplumber.service`
- install `sys-firmware/sof-firmware` on nvgen

## install and configure fonts

- emerge noto-cjk, noto-emoji, dejavu, fira-mono, fira-code
- eselect fontconfig enalbe <target>
- reboot
- download nerdfont.com zip file(s): all Ubuntu variants
- unzip into `~/.local/share/fonts`
- `fc-cache -fv`

## set up bluetooth

- enable bluetooth USE flag
- emerge bluez
- systemct bluetooth start
- make sure no firmware issues
- bluetoothctl
  - list
  - discoverable on
  - pairable on
  - scan
  - devices
  - pair <device_mac>
  - trust <device_mac>
  - connect <device_mac>
  - info <device_mac>
- used mictests.com to test microphone

# Future Enhancements

- touchpad palm rejection for nvgen
- power profiles and switching
- external monitors in hyprland
- telescope search icons in nvim for "disk" and see many squares and kanji
- root dotfiles
- build up from smaller profile
- keychain for ssh key
- enable (proton) vpn
- unlock luks root with usb device (storage or yubikey)

## Screen brightness buttons

WORKAROUND:
`echo 25000 > /sys/class/backlight/intel_backlight/brightness`
note that sys-power/acpilight comes with useful udev rules for allowing video
group write access

testing with `evtest` doesn't show any output when testing the keyboard device
'2', as these buttons are actually on 'event8'. Then the keypresses will
register. Note that the next song button etc. register on the evtest keyboard
event. None of the multimedia keys show up with wev/xev.

many forum/reddit posts suggest that blacklisting the 'hid_sensor_hub' module
should enable these buttons.

After blacklisting hid_sensor_hub, some new events show up with `evtest` and are
reordered, and the keypresses now register on the one that mentions "Consumer
Control" i.e. still /dev/input/event8.
