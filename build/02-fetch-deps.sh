#!/bin/bash
# 02-fetch-deps.sh — download OpenClash runtime dependencies into /in/offline-packages
# and verify them against offline-packages.manifest.json (the exact set used for v0.1.0).
#
# Kernel modules (kmod-*) MUST come from the kmiit feed: their kernel version hash
# (6.6.137~20a052f3...) has to match the kernel inside the kmiit factory image.
# 24.10-SNAPSHOT feeds move; if a sha256 no longer matches, the upstream package was
# rebuilt — check the version manually before using it.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=/in/offline-packages
mkdir -p "$OUT"
FEEDS="
https://kmiit.github.io/Redmi_AX3000_immortalwrt/redmi_ax3000-24.10/r0-cb4f52a
https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/base
https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/packages
https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/luci
"
python3 - "$HERE/offline-packages.manifest.json" "$OUT" $FEEDS <<'PY'
import gzip, hashlib, json, sys, urllib.request
manifest, out, feeds = sys.argv[1], sys.argv[2], sys.argv[3:]
want = {p["file"]: p["sha256"] for p in json.load(open(manifest))["packages"]}
index = {}
for f in feeds:
    data = gzip.decompress(urllib.request.urlopen(f + "/Packages.gz", timeout=60).read()).decode()
    for block in data.split("\n\n"):
        for line in block.splitlines():
            if line.startswith("Filename: "):
                index.setdefault(line[10:].split("/")[-1], f + "/" + line[10:])
bad = 0
for name, sha in want.items():
    url = index.get(name)
    if not url:
        print("MISSING in feeds:", name); bad += 1; continue
    blob = urllib.request.urlopen(url, timeout=120).read()
    got = hashlib.sha256(blob).hexdigest()
    open(f"{out}/{name}", "wb").write(blob)
    print(("OK      " if got == sha else "CHANGED ") + name)
    bad += got != sha
sys.exit(1 if bad else 0)
PY
