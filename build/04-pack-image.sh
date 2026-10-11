#!/bin/bash
# 04-pack-image.sh — inject OpenClash + deps into the stock kmiit rootfs and re-ubinize.
#
# Why not `make image` in ImageBuilder? It works, but with the core baked in the rootfs
# is ~30MB and overflows the 36MiB slot. Repacking the kmiit image directly keeps its
# kernel volume byte-identical and lets us drop what we don't need.
#
# Packages are unpacked by hand, so opkg postinst scripts do NOT run; the needed
# init links are created explicitly below.
#
# Optional: CUSTOM_UCI_DEFAULTS=/in/99-zzz-custom-net  (first-boot LAN/WAN/WiFi script,
#           see examples/). NEVER publish an image built with your own credentials.
#           ROOT_PASSWORD=...  bake a root password hash into /etc/shadow (private builds only).
set -e
HERE=$(cd "$(dirname "$0")/.." && pwd)
OC_IPK=${OC_IPK:-/in/luci-app-openclash_0.47.156_all.ipk}
cd /m
rm -rf root && unsquashfs -q -d root img/*/*vol-rootfs.ubifs
ST=root/usr/lib/opkg/status; INFO=root/usr/lib/opkg/info

inst() { # $1 = ipk
	rm -rf /tmp/p && mkdir -p /tmp/p/c /tmp/p/d
	tar xzf "$1" -C /tmp/p && tar xzf /tmp/p/control.tar.gz -C /tmp/p/c && tar xzf /tmp/p/data.tar.gz -C /tmp/p/d
	p=$(sed -n 's/^Package: //p' /tmp/p/c/control)
	grep -qx "Package: $p" $ST && { echo "skip $p (already in image)"; return; }
	cp -a /tmp/p/d/. root/
	for f in /tmp/p/c/*; do b=$(basename "$f"); [ "$b" = control ] && cp "$f" "$INFO/$p.control" || cp -a "$f" "$INFO/$p.$b"; done
	(cd /tmp/p/d && find . -mindepth 1 ! -type d | sed 's#^\.##') > "$INFO/$p.list"
	{ grep -E '^(Package|Version|Depends|Provides|Conflicts|Architecture):' /tmp/p/c/control
	  echo "Status: install user installed"; echo "Installed-Time: $(date +%s)"; echo; } >> $ST
	echo "add $p"
}
for f in /in/offline-packages/*.ipk; do inst "$f"; done

# slim OpenClash: drop the two bundled web dashboards and GeoSite.dat (~24MB uncompressed)
rm -rf /tmp/oc && mkdir -p /tmp/oc/x /tmp/oc/d
tar xzf "$OC_IPK" -C /tmp/oc/x && tar xzf /tmp/oc/x/data.tar.gz -C /tmp/oc/d
rm -rf /tmp/oc/d/usr/share/openclash/ui/metacubexd /tmp/oc/d/usr/share/openclash/ui/zashboard \
	/tmp/oc/d/etc/openclash/GeoSite.dat
(cd /tmp/oc/d && tar czf /tmp/oc/x/data.tar.gz --owner=0 --group=0 .)
(cd /tmp/oc/x && tar czf /tmp/oc/slim.ipk --owner=0 --group=0 ./debian-binary ./control.tar.gz ./data.tar.gz)
inst /tmp/oc/slim.ipk

# init links that postinst would normally create
ln -sf ../init.d/openclash root/etc/rc.d/S99openclash
ln -sf ../init.d/openclash root/etc/rc.d/K15openclash
# mount the mtd20 "ocdata" volume at /etc/openclash early in boot
install -m 755 "$HERE/files/etc/init.d/ocdata" root/etc/init.d/ocdata
ln -sf ../init.d/ocdata root/etc/rc.d/S11ocdata

if [ -n "$CUSTOM_UCI_DEFAULTS" ]; then
	install -m 755 "$CUSTOM_UCI_DEFAULTS" root/etc/uci-defaults/99-zzz-custom-net
	echo "!! private build: custom first-boot config included — do not publish"
fi
if [ -n "$ROOT_PASSWORD" ]; then
	HASH=$(openssl passwd -6 "$ROOT_PASSWORD")
	sed -i "s#^root:[^:]*:#root:$HASH:#" root/etc/shadow
	echo "!! private build: root password baked in — do not publish"
fi

mksquashfs root /m/rootfs.sqfs -noappend -root-owned -quiet -comp xz -b 256K
s=$(stat -c %s /m/rootfs.sqfs); echo "rootfs $s bytes = $(( (s+126975)/126976 )) LEBs (slot has ~264 usable)"
cp img/*/*vol-kernel.ubifs /m/kernel.bin
cat > /m/ubi.ini <<INI
[kernel]
mode=ubi
image=/m/kernel.bin
vol_id=0
vol_type=dynamic
vol_name=kernel
[rootfs]
mode=ubi
image=/m/rootfs.sqfs
vol_id=1
vol_type=dynamic
vol_name=rootfs
[rootfs_data]
mode=ubi
vol_id=2
vol_type=dynamic
vol_name=rootfs_data
vol_size=1MiB
vol_flags=autoresize
INI
mkdir -p /in/out
ubinize -o /in/out/ra81-immortalwrt-openclash-factory.ubi -p 128KiB -m 2048 -s 2048 /m/ubi.ini
ubireader_display_info /in/out/ra81-immortalwrt-openclash-factory.ubi | grep -E "Volume Name|reserved_pebs"
cd /in/out && sha256sum *.ubi *.gz 2>/dev/null | tee SHA256SUMS
