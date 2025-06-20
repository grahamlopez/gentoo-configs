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

- emerge utilities
- fstab

  - simply add entries for boot and root partitions. something like

    ```
    UUID=AB80-30E8          /boot           vfat            noauto,noatime  0 2
    UUID=5560cc59-93b2-423f-8ae5-a2b31fd14284 /   ext4      defaults,noatime  0 1
    ```

- systemd (from <https://wiki.gentoo.org/wiki/Handbook:AMD64/Installation/System#systemd_2>)
  - `systemctl preset-all --preset-mode=enable-only`
  - `systemctl preset-all`

### set up wireless networking

Mutually exclusive choices for network management include:

- dhcpcd <https://wiki.gentoo.org/wiki/Network_management_using_DHCPCD>
- systemd-networkd <https://wiki.gentoo.org/wiki/Systemd/systemd-networkd>
- NetworkManager

wpa_supplicant is used for network authentication, not management

Using just dhcpcd and wpa_supplicant, this method with systemd worked well:
<https://wiki.gentoo.org/wiki/Network_management_using_DHCPCD#Using_Systemd>
essentially, just

```
cp /etc/wpa_supplicant/wpa_supplicant.conf /etc/wpa_supplicant/wpa_supplicant-DEVNAME.conf
ln -s /lib/systemd/system/wpa_supplicant@.service wpa_supplicant@DEVNAME.service

<<kill any wpa_supplicant instances already running>>

systemctl daemon-reload
```

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

- blacklist nouveau in `/etc/modprobe.d/blacklist.conf` -`echo auto > /sys/bus/pci/devices/0000\:01\:00.0/power/control`
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

While working on boot optimizations, I decided to streamline the boot,
authentication, general startup process. For now, I am enabling autologin, as
these are single-user systems with full disk encryption anyway.

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

- use `lspci -k | grep -A3 Audio` to see if kernel is loading audio drivers
- enable pipewire-alsa and sound-server USE flags for pipewire
- `usermod -aG pipewire graham`
- `systemctl --user enable --now pipewire.service pipewire-pulse.service wireplumber.service`
- install `sys-firmware/sof-firmware` on nvgen
- then `wpctl status` to infos

sometimes, `wpctl status` shows only "Dummy Output" as a sink, where it should
be showing "Built-in Audio Analog Stereo [vol: 0.50]" for both "Sinks:"
and "Sources:", and "Built-in Audio [alsa]" for "Devices:".

I haven't yet figured out

1. what causes these to drop out, or
2. how to get them back without a reboot

## install and configure fonts

- emerge noto-cjk, noto-emoji, dejavu, fira-mono, fira-code
- eselect fontconfig enalbe <target>
- reboot
- download nerdfont.com zip file(s): all Ubuntu variants
- unzip into `~/.local/share/fonts`
- `fc-cache -fv`

Test some icons and emoji here in the browser:

```
    FIX = icon = " ",
    TODO = icon = " ",
    HACK = icon = " ",
    WARN = icon = " ",
    PERF = icon = " ",
    NOTE = icon = " ",
    TEST = icon = "⏲ ",

(╯°□°）╯︵ ┻━┻
¯\_(ツ)_/¯
```

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

# minimal UKI

- start with `make localmodconfig` if no defconfig available
  - `diff defconfig-flattop /usr/src/linux/defconfig | grep '^<'` on nvgen:

  ```
  < CONFIG_LOCALVERSION="-lopez64"
  < CONFIG_DEFAULT_HOSTNAME=""
  < CONFIG_INITRAMFS_SOURCE="/boot/initrd-lopez64.cpio.xz"
  < CONFIG_CMDLINE_BOOL=y
  < CONFIG_CMDLINE="root=UUID=5560cc59-93b2-423f-8ae5-a2b31fd14284 crypt_root=UUID=655caefd-7e35-4d53-a252-ca92ff7e1bdc ro root_trim=yes panic=10"
  < CONFIG_CMDLINE_OVERRIDE=y
  < CONFIG_BT_RFCOMM=m
  < CONFIG_BT_RFCOMM_TTY=y
  < CONFIG_BT_BNEP=m
  < CONFIG_BT_BNEP_MC_FILTER=y
  < CONFIG_BT_BNEP_PROTO_FILTER=y
  < CONFIG_RAPIDIO=m
  < CONFIG_BLK_DEV_NVME=y
  < CONFIG_DM_CRYPT=y
  < CONFIG_INPUT_UINPUT=y
  < CONFIG_GPIO_CROS_EC=m
  < CONFIG_CHARGER_CROS_USBPD=m
  < # CONFIG_CHARGER_CROS_PCHG is not set
  < CONFIG_VIDEO_OV13858=m
  < CONFIG_SND_HDA_CODEC_SIGMATEL=m
  < CONFIG_SND_USB_AUDIO=m
  < CONFIG_SND_USB_AUDIO_MIDI_V2=y
  < # CONFIG_SND_SOC_SOF_INTEL_SOUNDWIRE is not set
  < CONFIG_UHID=m
  < CONFIG_USB_STORAGE=y
  < CONFIG_LEDS_CLASS_MULTICOLOR=m
  < CONFIG_CROS_EC=m
  < CONFIG_CROS_EC_LPC=m
  < CONFIG_CROS_KBD_LED_BACKLIGHT=m
  < # CONFIG_CROS_EC_LIGHTBAR is not set
  < # CONFIG_CROS_EC_DEBUGFS is not set
  < # CONFIG_CROS_EC_SENSORHUB is not set
  < # CONFIG_CROS_EC_TYPEC is not set
  < # CONFIG_CROS_TYPEC_SWITCH is not set
  < # CONFIG_DCDBAS is not set
  < # CONFIG_DELL_RBTN is not set
  < # CONFIG_DELL_SMBIOS is not set
  < # CONFIG_DELL_WMI_DDV is not set
  < # CONFIG_DELL_WMI_SYSMAN is not set
  < CONFIG_SOUNDWIRE_INTEL=m
  < CONFIG_VFAT_FS=m
  < CONFIG_FAT_DEFAULT_IOCHARSET="ascii"
  < CONFIG_CRYPTO_CHACHA20_X86_64=y
  < CONFIG_CRYPTO_POLY1305_X86_64=y
  < # CONFIG_UBSAN_SIGNED_WRAP is not set
  ```

  so I copied most of these over. We'll be paring both kernels down over time.
- if savedefconfig is available
  - cp defconfig to /usr/src/linux/.config
  - `make olddefconfig`
- populate CONFIG_CMDLINE="root=UUID=<uuid of /dev/mapper/root> crypt_root=UUID=<uuid of /dev/nvme0n1p2> ro root_trim=yes panic=10"
- build the kernel with `KCFLAGS="-march=native -O2 -pipe" make -j12`
- install modules with `make modules_install INSTALL_MOD_STRIP=1`
- generate an initrd with `genkernel --luks initramfs`
- copy the generated initrd to `/root/initrd-<whatever>.cpio.xz` (or whatever compression)
- add the path to the initrd to CONFIG_INITRAMFS_SOURCE
- rebuild the kernel
- `cp arch/x86/boot/bzImage /boot/EFI/boot/boot64x.efi`
- `efibootmgr --create --disk /dev/nvme0n1 --part 1 --label "gentoo" --loader /EFI/boot/bootx64.efi`

# Future Enhancements

- touchpad palm rejection for nvgen
- power profiles and switching
- external monitors in hyprland
- telescope search icons in nvim for "disk" and see many squares and kanji
- build up from smaller (non-desktop) profile
- keychain for ssh key
- enable (proton) vpn
- unlock luks root with usb device (storage or yubikey)
- user mount removable devices
- screenlocking and fingerprint reader

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
