#!/bin/bash
# 01-setup.sh — prepare a Debian/Ubuntu build container.
# Usage (inside the container, inputs in /in):
#   docker run -it --name ra81ib -v $PWD/in:/in debian:trixie bash
#   bash /in/build/01-setup.sh
#
# Expected files in /in (download them yourself, see README "构建输入"):
#   immortalwrt-imagebuilder-qualcommax-ipq50xx.Linux-x86_64.tar.zst   (kmiit release)
#   immortalwrt-qualcommax-ipq50xx-redmi_ax3000-squashfs-factory.ubi   (kmiit release)
#   luci-app-openclash_0.47.156_all.ipk                                (vernesong/OpenClash)
#   offline-packages/*.ipk                                             (deps, see 02-fetch-deps.sh)
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq build-essential gawk file unzip rsync zstd xz-utils bzip2 \
	wget curl ca-certificates squashfs-tools mtd-utils python3-pip libncurses-dev
pip install -q --break-system-packages ubi_reader 2>/dev/null || pip install -q ubi_reader

mkdir -p /work /m
cd /work && tar --zstd -xf /in/immortalwrt-imagebuilder-qualcommax-ipq50xx.Linux-x86_64.tar.zst

# unpack the stock kmiit factory image: kernel + rootfs squashfs
cd /m && rm -rf img
ubireader_extract_images -o /m/img /in/immortalwrt-qualcommax-ipq50xx-redmi_ax3000-squashfs-factory.ubi
ls -la /m/img/*/
echo "setup OK"
