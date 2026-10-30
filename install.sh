#!/bin/bash

# 
# This file originates from Kite's Circuit Sword control board project.
# Author: Kite (Giles Burgess)
# 
# THIS HEADER MUST REMAIN WITH THIS FILE AT ALL TIMES
#
# This firmware is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This firmware is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this repo. If not, see <http://www.gnu.org/licenses/>.
#

if [ "$EUID" -ne 0 ]
  then echo "Please run as root (sudo)"
  exit 1
fi

if [ $# == 0 ] || [ $# == 3 ] ; then
  echo "Usage: ./<cmd> YES [branch] [fat32 root] [ext4 root]"
  exit 1
fi

#####################################################################
# Vars

if [[ $3 != "" ]] ; then
  DESTBOOT=$3
else
  DESTBOOT="/boot"
fi

if [[ $4 != "" ]] ; then
  DEST=$4
else
  DEST=""
fi

GITHUBPROJECT="Circuit-Sword"
GITHUBURL=${CS_REPO_URL:-"https://github.com/jamesalmeida/$GITHUBPROJECT"}
PIHOMEDIR="$DEST/home/pi"
BINDIR="$PIHOMEDIR/$GITHUBPROJECT"
USER="pi"

# krextra/es-theme-pixel master, 2018-12-19; pinned so every build is the same
PIXEL_THEME_COMMIT="50918176ba339ba7bb17b17f53cf94bc3d095d12"

if [[ $2 != "" ]] ; then
  BRANCH=$2
else
  BRANCH="master"
fi

#####################################################################
# Functions
execute() { #STRING
  if [ $# != 1 ] ; then
    echo "ERROR: No args passed"
    exit 1
  fi
  cmd=$1
  
  echo "[*] EXECUTE: [$cmd]"
  eval "$cmd"
  ret=$?
  
  if [ $ret != 0 ] ; then
    echo "ERROR: Command exited with [$ret]"
    exit 1
  fi
  
  return 0
}

exists() { #FILE
  if [ $# != 1 ] ; then
    echo "ERROR: No args passed"
    exit 1
  fi
  
  file=$1
  
  if [ -f $file ]; then
    echo "[i] FILE: [$file] exists."
    return 0
  else
    echo "[i] FILE: [$file] does not exist."
    return 1
  fi
}

# Unpack a bundled .deb over $DEST without dpkg -x, whose tar replaces
# directory symlinks: on merged-/usr images it turns /lib -> usr/lib into a
# plain directory and the image no longer boots.
extract_deb() { #DEB
  (set -o pipefail; dpkg-deb --fsys-tarfile "$1" | tar -x --keep-directory-symlink -C "$DEST/")
}

#####################################################################
# LOGIC!
echo "INSTALLING.."

# This installer targets legacy RetroPie images that mount the boot partition at
# /boot. Bookworm and later mount it at /boot/firmware and need the separate
# setup in docs/bookworm-bringup.md; writing /boot/config.txt there does nothing.
FSTAB_BOOT=$(awk '$1 !~ /^#/ && $3 == "vfat" { print $2; exit }' "$DEST/etc/fstab" 2>/dev/null)
if [[ -n "$FSTAB_BOOT" && "$FSTAB_BOOT" != "/boot" ]] ; then
  echo "ERROR: The boot partition is mounted at [$FSTAB_BOOT], not /boot. install.sh only supports legacy RetroPie images; see docs/bookworm-bringup.md"
  exit 1
fi

# Own files by the image's uid/gid, which the build host may not know by name.
OWNER=$(awk -F: -v user="$USER" '$1 == user { print $3 ":" $4; exit }' "$DEST/etc/passwd")
if [[ -z "$OWNER" ]] ; then
  echo "ERROR: User [$USER] does not exist in [$DEST/etc/passwd]"
  exit 1
fi

# Check dependencies before changing boot files or installing Python 3 callers.
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
bash "$SCRIPT_DIR/settings/install-python3-deps.sh" "${DEST:-/}" || exit 1

# Checkout code if not already done so
if ! exists "$BINDIR/LICENSE" ; then
  execute "git clone --recursive --depth 1 --branch $BRANCH $GITHUBURL $BINDIR"
fi
execute "chown -R $OWNER $BINDIR"

#####################################################################
# Copy required to /boot

# Config.txt bits
if ! exists "$DESTBOOT/config_ORIGINAL.txt" ; then
  execute "cp $DESTBOOT/config.txt $DESTBOOT/config_ORIGINAL.txt"
  execute "cp $BINDIR/settings/config.txt $DESTBOOT/config.txt"
  execute "cp $BINDIR/settings/config-cs.txt $DESTBOOT/config-cs.txt"
fi

# Special case where config.txt has been updated on upgrade
if [[ ! $(grep "CS CONFIG VERSION: 1.0" "$DESTBOOT/config.txt") ]] ; then
  execute "cp $BINDIR/settings/config.txt $DESTBOOT/config.txt"
fi

#####################################################################
# Copy required to /

# Copy USB sound
execute "cp $BINDIR/settings/asound.conf $DEST/etc/asound.conf"
execute "cp $BINDIR/settings/alsa-base.conf $DEST/etc/modprobe.d/alsa-base.conf"

# Copy autostart
if ! exists "$DEST/opt/retropie/configs/all/autostart_ORIGINAL.sh" ; then
  execute "mv $DEST/opt/retropie/configs/all/autostart.sh $DEST/opt/retropie/configs/all/autostart_ORIGINAL.sh"
  execute "cp $BINDIR/settings/splashscreen.list $DEST/etc/splashscreen.list"
fi
execute "cp $BINDIR/settings/autostart.sh $DEST/opt/retropie/configs/all/autostart.sh"
execute "chown $OWNER $DEST/opt/retropie/configs/all/autostart.sh"

# Copy ES safe shutdown script
execute "cp $BINDIR/settings/cs_shutdown.sh $DEST/opt/cs_shutdown.sh"

# Fix splashsreen sound
if exists "$DEST/etc/init.d/asplashscreen" ; then
  execute "sed -i \"s/ *both/ alsa/\" $DEST/etc/init.d/asplashscreen"
fi
if exists "$DEST/opt/retropie/supplementary/splashscreen/asplashscreen.sh" ; then
  execute "sed -i \"s/ *both/ alsa/\" $DEST/opt/retropie/supplementary/splashscreen/asplashscreen.sh"
fi

# Fix audio
if exists "$DEST/opt/retropie/emulators/mupen64plus/bin/mupen64plus.sh" ; then
  execute "sed -i \"s/mupen64plus-audio-omx/mupen64plus-audio-sdl/\" $DEST/opt/retropie/emulators/mupen64plus/bin/mupen64plus.sh"
fi

# Fix audio
if ! exists "$PIHOMEDIR/.vice/sdl-vicerc" ; then
  execute "mkdir -p $PIHOMEDIR/.vice/"
  execute "echo 'SoundOutput=2' > $PIHOMEDIR/.vice/sdl-vicerc"
  execute "chown -R $OWNER $PIHOMEDIR/.vice/"
fi

# Install the pixel theme and set it as default
if ! exists "$DEST/etc/emulationstation/themes/pixel/system/theme.xml" ; then
  execute "mkdir -p $DEST/etc/emulationstation/themes"
  execute "rm -rf $DEST/etc/emulationstation/themes/pixel"
  execute "git init -q $DEST/etc/emulationstation/themes/pixel"
  execute "git -C $DEST/etc/emulationstation/themes/pixel fetch -q --depth 1 https://github.com/krextra/es-theme-pixel.git $PIXEL_THEME_COMMIT"
  execute "git -C $DEST/etc/emulationstation/themes/pixel checkout -q FETCH_HEAD"
  execute "cp -p $BINDIR/settings/es_settings.cfg $DEST/opt/retropie/configs/all/emulationstation/es_settings.cfg"
  execute "sed -i \"s/carbon/pixel/\" $DEST/opt/retropie/configs/all/emulationstation/es_settings.cfg"
fi

# Install runcommand splash
#if ! exists "$DEST/opt/retropie/configs/desktop/launching.png" ; then
#  execute "rm -rf /tmp/es-runcommand-splash"
#  execute "git clone --recursive --depth 1 --branch master https://github.com/ehettervik/es-runcommand-splash.git /tmp/es-runcommand-splash"
#  execute "chown -R $USER:$USER /tmp/es-runcommand-splash"
#  execute "cp -rp /tmp/es-runcommand-splash/* $DEST/opt/retropie/configs"
#  execute "rm -rf /tmp/es-runcommand-splash"
#fi

# Install the reboot to hdmi scripts
execute "cp $BINDIR/settings/reboot_to_hdmi.sh $PIHOMEDIR/RetroPie/retropiemenu/reboot_to_hdmi.sh"
execute "cp -p $BINDIR/settings/reboot_to_hdmi.png $PIHOMEDIR/RetroPie/retropiemenu/icons/reboot_to_hdmi.png"
if [[ ! $(grep "reboot_to_hdmi" "$DEST/opt/retropie/configs/all/emulationstation/gamelists/retropie/gamelist.xml") ]] ; then
  execute "sed -i 's|</gameList>|  <game>\n    <path>./reboot_to_hdmi.sh</path>\n    <name>One Time Reboot to HDMI</name>\n    <desc>Enable HDMI and automatically reboot for it to apply. The subsequent power cycle will revert back to the internal screen. It is normal when enabled for the internal screen to remain grey/white.</desc>\n    <image>/home/pi/RetroPie/retropiemenu/icons/reboot_to_hdmi.png</image>\n  </game>\n</gameList>|g' $DEST/opt/retropie/configs/all/emulationstation/gamelists/retropie/gamelist.xml"
fi

# Enable 30sec autosave
execute "sed -i \"s/# autosave_interval =/autosave_interval = \"30\"/\" $DEST/opt/retropie/configs/all/retroarch.cfg"

# Disable 'wait for network' on boot
execute "rm -f $DEST/etc/systemd/system/dhcpcd.service.d/wait.conf"

# Remove wifi country disabler
execute "rm -f $DEST/etc/systemd/system/multi-user.target.wants/wifi-country.service"

# Copy wifi firmware
execute "cp $BINDIR/wifi-firmware/rtl* $DEST/lib/firmware/rtlwifi/"

# Install rfkill
execute "extract_deb $BINDIR/settings/rfkill_0.5-1_armhf.deb"

# Install avrdude
execute "extract_deb $BINDIR/settings/avrdude_6.3+r1425-1+rpt1_armhf.deb"
execute "extract_deb $BINDIR/settings/libftdi1_0.20-4_armhf.deb"

# Install wiringPi
execute "extract_deb $BINDIR/settings/wiringpi_2.46_armhf.deb"

# Enable /ramdisk as a tmpfs (ramdisk)
if [[ $(grep '/ramdisk' $DEST/etc/fstab) == "" ]] ; then
  execute "echo 'tmpfs    /ramdisk    tmpfs    defaults,noatime,nosuid,size=100k    0 0' >> $DEST/etc/fstab"
fi

# Remove the old service
execute "rm -f $DEST/etc/systemd/system/cs-osd.service"
execute "rm -f $DEST/etc/systemd/system/multi-user.target.wants/cs-osd.service"
execute "rm -f $DEST/lib/systemd/system/cs-osd.service"

# Prepare for service install
execute "rm -f $DEST/etc/systemd/system/cs-hud.service"
execute "rm -f $DEST/etc/systemd/system/multi-user.target.wants/cs-hud.service"
execute "rm -f $DEST/lib/systemd/system/cs-hud.service"

execute "rm -f $DEST/lib/systemd/system/dpi-cloner.service"

# Install HUD service
execute "cp $BINDIR/cs-hud/cs-hud.service $DEST/lib/systemd/system/cs-hud.service"

#execute "systemctl enable cs-hud.service"
execute "ln -s /lib/systemd/system/cs-hud.service $DEST/etc/systemd/system/cs-hud.service"
execute "ln -s /lib/systemd/system/cs-hud.service $DEST/etc/systemd/system/multi-user.target.wants/cs-hud.service"

# Install DPI-CLONER service
execute "cp $BINDIR/dpi-cloner/dpi-cloner.service $DEST/lib/systemd/system/dpi-cloner.service"

if [[ $DEST == "" ]] ; then
  execute "systemctl daemon-reload"
  execute "systemctl start cs-hud.service"
fi

#####################################################################
# DONE
echo "DONE!"
