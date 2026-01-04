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
  - emerge-webrsync
  - set up portage to use git (<https://wiki.gentoo.org/wiki/Portage_with_Git>)
    - umount /dev/shm
    - mount --types tmpfs --options nosuid,nodev shm /dev/shm
    - emerge gentoo-repository dev-vcs/git
    - do onetime stuff from that page to convert from rsync if needed
      - eselect repository remove -f gentoo
      - rm -rf /var/db/repos/gentoo
      - eselect repository add gentoo git https://github.com/gentoo-mirror/gentoo.git
    - `emaint sync` to synchronize all enabled repos (simialr to emerge --sync)
- set the profile (desktop/systemd)
- set the timezone (defer if dual booting)
- configure locales
  - edit /etc/locale.gen
  - `locale-gen`
  - eselect locale list

## install firmware and kernel

- emerge linux-firmware, gentoo-kernel
  - savedconfig
- `genkernel --luks initramfs`
- set up efibootmgr
  - `efibootmgr --create --index 5 --disk /dev/nvme0n1 --part 1 --label "gentoo-alt" --loader /EFI/boot/bootx64-alt.efi --unicode 'crypt_root=UUID=63fdec71-9236-43d1-8d4a-2f3afba7d59a root=UUID=f81baa5e-121b-4983-ab30-020d89fbe1f1 ro initrd=/EFI/boot/initrd-alt root_trim=yes'`
- re-emerge systemd with USE=cryptsetup (or just update world)

## final configuration

- set root password
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
cd /etc/systemd/system/multi-user.target.works
ln -s /lib/systemd/system/wpa_supplicant@.service wpa_supplicant@DEVNAME.service

<<kill any wpa_supplicant instances already running>>

systemctl daemon-reload
```

Enable dhcpcd.

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

If no session gets created (i.e. Hyprland complains about no XDG_RUNTIME_DIR) I
traced this back to an "Input/Output error" with pam_systemd.so (seen via
`systemctl status systemd-logind.service` or `journalctl -b | grep pam` etc).

After much debugging, hardware tests, etc, I discovered that disabling
`systemd-userdbd` was the only workaround, and though maybe not recommended(?),
it is the case on flattop, so going with it for now.

```
systemctl disable systemd-userdbd
```

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

- install xdg-desktop-portal-gtk
- reboot
- `gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'`
- set up keyd
  - `capslock = overload(control, esc)`

## streamline boot/login

While working on boot optimizations, I decided to streamline the boot,
authentication, general startup process. For now, I am enabling autologin, as
these are single-user systems with full disk encryption anyway.

- sudo for passwordless root: `visudo` and add `graham ALL=NOPASSWD: /bin/su -`
- terminal login: edit `/etc/systemd/system/getty@tty1.service.d/override.conf`

  ```
  [Service]
  ExecStart=
  ExecStart=-/sbin/agetty --autologin <username> --noclear %I linux
  ```

  then `systemctl daemon-reload` and `systemctl restart getty@tty1`
  Can always start debugging issues with `journalctl -u getty@tty1.service`

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
- then `wpctl status` to show info

sometimes, `wpctl status` shows only "Dummy Output" as a sink, where it should
be showing "Built-in Audio Analog Stereo [vol: 0.50]" for both "Sinks:"
and "Sources:", and "Built-in Audio [alsa]" for "Devices:".

I haven't yet figured out

1. what causes these to drop out, or
2. how to get them back without a reboot

For example, on nvgen after a distribution gentoo-kernel upgrade, sound worked
with the dist kernel, but no longer with my (unchanged) gentoo-sources kernel. I
booted into the dist kernel and used `make localmodconfig` and rebuilt. This
didn't work. So I took the .config from the dist kernel and manually copied
everything sound related over to the .config for my kernel. This worked. The
defconfig is saved in the repo. FIXME: this nvgen kernel needs to be re-minimized

## install and configure fonts

ghostty has a zero configuration philosophy, so maybe start there. kitty also
comes with nerd fonts pre-installed.

despite passing my font smoke test scripts, the arrow icon in the default
whichkey interface was still missing, as well as the fonts in the telescope
picker.

- emerge noto-cjk, noto-emoji, dejavu, fira-mono, fira-code
- eselect fontconfig enalbe <target>
- reboot
- download nerdfonts.com zip file(s): all Ubuntu variants
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

I like the horizontal compactness of the Ubuntu\* nerd fonts, but their symbols
are very small compared to the Fira and Liberation system fonts (that I assume
are both taking symbols from the media-fonts/symbols-nerd-font package. Those
symbols are much nicer to read, but there are more missing compared to those
downloaded directly from nerdfonts.com.

update: I downloaded and tried (via `kitten choose-fonts`) a whole bunch of
fonts from nerdfonts.com, and discovered the large icons come from the
difference between there being a "Mono" at the and of the font package name
itself.

## set up bluetooth

- enable bluetooth USE flag
- emerge bluez
- systemct bluetooth start
- make sure no firmware issues
- bluetoothctl
  - list
  - discoverable on
  - pairable on
  - scan on
  - devices
  - pair <device_mac>
  - trust <device_mac>
  - connect <device_mac>
  - info <device_mac>
- used mictests.com to test microphone

# minimal UKI

## Custom kernel

DO NOT CUSTOMIZE the gentoo-kernel distribution kernel. With my current level of
knowledge, it isn't worth it. Disadvantages

- no reuse of incremental builds
- difficult to get a working boot with even only minimal changes to savedconfig

configuring a custom kernel:

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

so I copied most of these over. TODO: We'll be paring both kernels down over time.

## Commandline + initrd

<https://wiki.gentoo.org/wiki/Kernel/Command-line_parameters>

`cat /proc/cmdline` to see the command line of the currently running kernel

Three ways to pass parameters to the kernel

1. Kconfig (build them into the kernel)
2. UEFI (using efibootmgr --unicode)
3. various bootloaders e.g. grub, lilo, systemd-boot

building in the command line `CONFIG_CMDLINE` by itself results in the root
device not being found and kernel panic at boot (no decrypt prompt) so build in
the initrd as well. Some online sources (don't remember where) said that an
embedded command line doesn't work well without a built-in initrd.

learned that CONFIG_CMDLINE_OVERRIDE is likely needed, especially for stub
booting

Here is the recipe:

- if savedefconfig is available
  - cp defconfig to /usr/src/linux/.config
  - `make olddefconfig`
- populate CONFIG_CMDLINE="root=UUID=<uuid of /dev/mapper/root> crypt_root=UUID=<uuid of /dev/nvme0n1p2> ro root_trim=yes panic=10"
- enable CONFIG_CMDLINE_OVERRIDE
- make necessary things built-in and not modules (see .config progression)
  - so far I know DM_CRYPT can be either built-in or a module (in the initrd)
- build the kernel with `KCFLAGS="-march=native -O2 -pipe" make -j12`
- install modules with `make modules_install INSTALL_MOD_STRIP=1`
  - this noticeably affects boot speed
- generate an initrd with `genkernel --luks initramfs`
- copy the generated initrd to `/root/initrd-<whatever>.cpio.xz` (or whatever compression)
- add the path to the initrd to CONFIG_INITRAMFS_SOURCE
- rebuild the kernel
- `cp arch/x86/boot/bzImage /boot/EFI/boot/boot64x.efi`
- `efibootmgr --create --disk /dev/nvme0n1 --part 1 --label "gentoo" --loader /EFI/boot/bootx64.efi`

## Firmware

<https://wiki.gentoo.org/wiki/Linux_firmware>

FIXED:
`dmesg | grep -i firmware` to see what was loaded

enable savedconfig USE flag, edit in /etc/portage/savedconfig, and reemerge

FIXME: do I need cpu microcode? (<https://wiki.gentoo.org/wiki/Microcode>)

How do I know if my cpu needs microcode, and if it is being applied?

I see `amd-uc.img` in `/boot` but I don't know if I need to be e.g. adding that
into the initrd, etc.?

## nvidia drivers

for bequiet with the Quadro P620 (Pascal) installed, nouveau drivers do work
with wayland/hyprland, but the performance is poor enough to notice during
normal usage (choppy mouse cursor, slow window movements).

To enable, set `VIDEO_CARDS="nouveau"` in `/etc/portage/make.conf` 

Attempting to use x11-drivers/nvidia-drivers. For right now on bequiet, I'm
using a distribution kernel so enabling the `dist-kernel` use flag; `wayland`
use flag is already enabled.

I ended up emerging nvidia-drivers, then based on warnings I saw from it about
the kernel being built with an older GCC, I emerged gentoo-kernel, then
nvidia-drivers again. Then a normal `genkernel --luks initramfs`, put the images
into `/EFI/boot` and it seems to work fine. The nvidia-drivers package
installed a `/etc/modprobe.d/nvidia.conf` and whatever else it needed.

# Future Enhancements

A big list of ideas of things I've wanted to try at some point. Some are very
low effort, some are very high.

- port omarchy to gentoo
- touchpad palm rejection for nvgen
- power profiles and switching
- define some useful package sets (<https://wiki.gentoo.org/wiki/Package_sets#Custom_sets>)
- unlock luks root with usb device (storage or yubikey)
- external monitors in hyprland
- keychain for ssh key
- enable (proton) vpn
- build up from smaller (non-desktop) profile
- telescope search icons in nvim for "disk" and see many squares and kanji
- screenlocking and fingerprint reader
- user mount removable devices
- boot aesthetics: speed, plymouth and disk unlock
- more theming (with fast/auto switching): wallpaper+colors/pywal16+fonts
- virutalization:
  - qemu for kernel/boot debugging
  - lightweight containers for linux (lxc, podman, etc.)
  - gentoo prefix
  - gentoo in WSL
  - lookinglass for windows
  - https://github.com/quickemu-project/quickemu
  - https://github.com/HikariKnight/QuickPassthrough

## Screen brightness buttons

`echo 25000 > /sys/class/backlight/intel_backlight/brightness`
note that sys-power/acpilight comes with useful udev rules for allowing video
group write access

testing with `evtest` doesn't show any output when testing the keyboard device
'2', as these buttons are actually on 'event8'. Then the keypresses will
register. Note that the next song button etc. register on the evtest keyboard
event. None of the multimedia keys show up with wev/xev.

## Improve terminal themes

need better (more contrasty) light theme colors

it would be cool to be able to dynamically/interactively change the themes like
I do with neovim

### zsh, tmux, dir_colors

ensure these follow along nicely

### change transparency on the fly or based on dark/light

this may not really be possible in ghostty

probably eventually combine with light/dark theme switching

how to get kitty to reload its config in all running instances? This isn't
really possible, but you can get it to reload its config file with ctrl+shift+F5
or with `kill -SIGUSR1 <kitty_pid>`

so for kitty:

- background_opacity isn't supported in the theme files
- have a separate, single line file with `background_opacity` that is included
  in the main kitty.conf. Do not put this file under version control because it
  will get changed all the time
- now can script `echo "background_opacity 0.8" > ~/.config/kitty/opacity.conf`
  and a `kill -SIGUSR1 <kitty_pids>` to dynamically change

for ghostty, the only way to force a config reload is to interactively use a
keyboard shortcut. But this is probably okay as a workaround, as I usually don't
have too many terminals open and don't change themes too often.

## hyprland complaints

When starting kitty from a terminal:

```
[0.110] [glfw error 65544]: process_desktop_settings: failed with error: [org.freedesktop.DBus.Error.UnknownMethod] No such interface “org.freedesktop.portal.Settings” on object at path /org/freedesktop/portal/desktop
```

suggest installing and starting xdg-desktop-portal-hyprland (via guru overlay)

```
[0.110] [glfw error 65544]: Notify: Failed to get server capabilities error: [org.freedesktop.DBus.Error.ServiceUnknown] The name org.freedesktop.Notifications was not provided by any .service files
```

suggest installing and starting a notification service
<https://www.perplexity.ai/search/how-do-i-solve-the-following-e-RjBEBexwSeusYywGKEiBTg#1>

```
[0.148] Could not move child process into a systemd scope: [Errno 5] Failed to call StartTransientUnit: org.freedesktop.DBus.Error.Spawn.ChildExited: Process org.freedesktop.systemd1 exited with status 1
```

## systemd - other

systemd can handle automatic parition mounting, but I'm not yet sure how
this works with luks encryption, or if I want this over /etc/fstab
(<https://wiki.gentoo.org/wiki/Systemd#Automatic_mounting_of_partitions_at_boot>)

there are a load of USE flags for systemd; there might be some interesting
things to take advantage of. (<https://wiki.gentoo.org/wiki/Systemd#USE_flags>)

verbosity of boot messages can be tweaked
<https://wiki.gentoo.org/wiki/Systemd#Configure_verbosity_of_boot_process>

systemd-bootchart will show boot process performance. It requires the `boot` USE
flag, but this also installs the systemd-boot bootloader, so probably want to
look at 3rd-party utilities for profiling

## kitty clean exit with disowned process

use `nohup [command] &> /dev/null &`

This makes using kitty as the dropdown terminal less useful

after backgrounding and disowning a process in the kitty terminal, pressing
ctrl+d to close the shell+terminal causes a hang

adding to `.config/kitty/kitty.conf` didn't help:

```
shell_integration enabled  # Ensure proper shell state tracking
confirm_os_window_close -1 # Disable exit confirmation prompts[4]
```

## personal overlay packages

<https://github.com/XAMPPRocky/tokei>

What creating a package for system configurations?

Things I have wanted at some point in the past:

- impala
- kmonad binary release (alternatives: kanata, keyd)
- sasl oauth2 plugin
- onlykey app
- miniconda
- nvhpc
- config files
- freeplane
- logseq
- gensys (my project)
- sakaki's tools (buildkernel, etc.)
- my savedconfigs
- my kernel image that can be put on an sd card and boot any of my machines
- terminal fun things:
  - <https://github.com/cmatsuoka/asciiquarium>
  - <https://gitlab.com/jallbrit/cbonsai>
  - <https://github.com/bartobri/no-more-secrets>

## binhost

I first need to get threadripper reinstalled to more closely match the profile
and USE flags of nvgen and flattop

<https://wiki.gentoo.org/wiki/Binary_package_guide#Creating_binary_packages>
<https://www.gentoo.org/news/2024/02/04/x86-64-v3.html>
