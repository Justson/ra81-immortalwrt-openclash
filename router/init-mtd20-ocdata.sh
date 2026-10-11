#!/bin/sh
# init-mtd20-ocdata.sh  —  run ON THE ROUTER, AFTER ImmortalWrt has booted.
# Creates an "ocdata" UBIFS volume on the spare "overlay" partition (mtd20),
# seeds it with the current /etc/openclash, and installs the mihomo core.
# SAFE: touches ONLY the overlay partition. Never writes rootfs / rootfs_1.
set -e

CORE_GZ=/tmp/clash_meta.gz
CORE_SHA=f4408c7a2d51578479ce8706b6b3dfa3dad542bd6fa415d77b157c51c4f7d462  # sha256 of decompressed core

[ -f "$CORE_GZ" ] || { echo "ERROR: $CORE_GZ not found. scp it to /tmp first."; exit 1; }

# --- locate overlay mtd and refuse anything else ---
MTD=$(grep '"overlay"' /proc/mtd | cut -d: -f1 | tr -dc 0-9)
[ -n "$MTD" ] || { echo "ERROR: no 'overlay' partition in /proc/mtd"; exit 1; }
NAME=$(sed -n "s/^mtd$MTD: [0-9a-f]* [0-9a-f]* \"\(.*\)\"/\1/p" /proc/mtd)
[ "$NAME" = "overlay" ] || { echo "ERROR: mtd$MTD is '$NAME', not overlay. ABORT."; exit 1; }
echo ">> overlay = mtd$MTD"

# --- detach any ubi currently bound to this mtd ---
for d in /sys/class/ubi/ubi[0-9]*; do
	[ -e "$d/mtd_num" ] || continue
	if [ "$(cat "$d/mtd_num")" = "$MTD" ]; then
		echo ">> detaching existing ${d##*/}"
		ubidetach -m "$MTD" || true
	fi
done

# --- format, attach, create volume ---
echo ">> formatting mtd$MTD (overlay) ..."
ubiformat /dev/mtd$MTD -y
ubiattach -m "$MTD"
UBI=
for d in /sys/class/ubi/ubi[0-9]*; do
	[ "$(cat "$d/mtd_num" 2>/dev/null)" = "$MTD" ] && UBI=${d##*/}
done
[ -n "$UBI" ] || { echo "ERROR: ubiattach did not create a ubi device"; exit 1; }
echo ">> attached as $UBI"
ubimkvol /dev/$UBI -N ocdata -m

# --- seed with current /etc/openclash and install core ---
mkdir -p /mnt/ocdata
mount -t ubifs "$UBI:ocdata" /mnt/ocdata
cp -a /etc/openclash/. /mnt/ocdata/ 2>/dev/null || true
mkdir -p /mnt/ocdata/core
gzip -dc "$CORE_GZ" > /mnt/ocdata/core/clash_meta
chmod 755 /mnt/ocdata/core/clash_meta

# --- verify core integrity ---
GOT=$(sha256sum /mnt/ocdata/core/clash_meta | cut -d' ' -f1)
if [ "$GOT" != "$CORE_SHA" ]; then
	echo "ERROR: core sha mismatch ($GOT). ABORT, not rebooting."
	umount /mnt/ocdata; exit 1
fi
sync
echo ">> core OK:"; ls -la /mnt/ocdata/core/clash_meta
echo ">> ocdata contents:"; ls /mnt/ocdata
umount /mnt/ocdata

echo
echo "DONE. Now run: reboot"
echo "After reboot, S11ocdata mounts ocdata at /etc/openclash and OpenClash finds the core."
