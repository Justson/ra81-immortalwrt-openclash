#!/bin/bash
# 03-build-mihomo.sh — build a slim mihomo (Clash.Meta) core for arm64.
# Dropping the gVisor stack (no "with_gvisor" tag) and stripping symbols shrinks the core
# from ~57MB to ~47MB (xz: 13.6MB -> 11.4MB). It still does not fit the 36MiB rootfs,
# which is why the core lives on the spare mtd20 "overlay" partition (see README).
# Output: /in/out/clash_meta.gz  (the image has gzip but NO xz decompressor)
set -e
VER=${MIHOMO_VERSION:-v1.19.32}
GO=${GO_VERSION:-1.25.3}
cd /tmp
[ -d /usr/local/go ] || { wget -q "https://go.dev/dl/go$GO.linux-amd64.tar.gz" -O go.tgz && tar xzf go.tgz -C /usr/local; }
export PATH=/usr/local/go/bin:$PATH
# export GOPROXY=https://goproxy.cn,direct   # uncomment inside mainland China
[ -d mihomo ] || { wget -q "https://github.com/MetaCubeX/mihomo/archive/refs/tags/$VER.tar.gz" -O m.tgz \
	&& mkdir mihomo && tar xzf m.tgz -C mihomo --strip-components=1; }
cd mihomo
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -trimpath \
	-ldflags "-s -w -buildid= -X github.com/metacubex/mihomo/constant.Version=$VER" \
	-o /tmp/clash_meta .
mkdir -p /in/out
gzip -9 -c /tmp/clash_meta > /in/out/clash_meta.gz
sha256sum /tmp/clash_meta /in/out/clash_meta.gz
