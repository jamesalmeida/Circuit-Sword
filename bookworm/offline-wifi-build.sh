#!/bin/bash
# Round 3: offline build of the RTL8723BS SDIO Wi-Fi driver, then reboot normally.
FW=/boot/firmware; mountpoint -q $FW || mount $FW
OUT=$FW/diag; mkdir -p $OUT; exec > $OUT/run.txt 2>&1; set -x
date; K=$(uname -r)
cd $FW/cs-wifi
apt-get install -y --no-install-recommends ./*.deb || dpkg -i --skip-same-version ./*.deb
gcc --version | head -1; ls -d /lib/modules/$K/build
SRC=/usr/src/rtl8723bs-cs; rm -rf $SRC; mkdir -p /usr/src
tar -C /usr/src -xzf rtl8723bs-src.tar.gz && mv /usr/src/rtl8723bs $SRC && cp SOURCE.txt $SRC/
find $SRC -exec touch {} +
time make -C /lib/modules/$K/build M=$SRC CONFIG_RTL8723BS=m modules -j4 > $OUT/build.txt 2>&1; echo "build exit $?"
tail -20 $OUT/build.txt
if [ -f $SRC/r8723bs.ko ]; then
  mkdir -p /lib/modules/$K/updates && cp $SRC/r8723bs.ko /lib/modules/$K/updates/ && depmod -a
  modprobe -v r8723bs; sleep 8
  lsmod | grep 8723; dmesg | grep -iE "8723|rtl|wlan|firmware" | tail -20
  systemctl start NetworkManager; sleep 40
  nmcli -t device; ip -4 a
fi
vcgencmd get_config int | grep -i rotate
cp $FW/cmdline.txt.orig $FW/cmdline.txt
date; sync
