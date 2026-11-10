#!/bin/bash
# Build OpenWrt for the D-Link DSR-1000N (rev A1) from a clean v25.12.6 checkout.
# Usage: ./build.sh [workdir]    (default workdir: ./openwrt-build)
# Needs a normal OpenWrt build host (Debian/Ubuntu with the usual build dependencies).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="${1:-$HERE/openwrt-build}"
BASE="$(cat "$HERE/OPENWRT_BASE")"

if [ ! -d "$WORK/.git" ]; then
  git clone --branch v25.12.6 https://github.com/openwrt/openwrt.git "$WORK"
fi
cd "$WORK"
[ "$(git rev-parse HEAD)" = "$BASE" ] || { echo "Expected OpenWrt $BASE (v25.12.6), got $(git rev-parse HEAD)"; exit 1; }

if ! git apply --check --reverse "$HERE/openwrt-v25.12.6-dlink-dsr-1000n.patch" 2>/dev/null; then
  git apply "$HERE/openwrt-v25.12.6-dlink-dsr-1000n.patch"
fi

./scripts/feeds update -a
./scripts/feeds install -a
cp "$HERE/dsr1000n.diffconfig" .config
make defconfig
make -j"$(nproc)" download
make -j"$(nproc)"

echo
echo "Images:"
ls -l bin/targets/octeon/generic/*dlink_dsr-1000n*
echo
echo "  *-initramfs-kernel.bin   boot from RAM over TFTP (testing, recovery)"
echo "  *-squashfs-sysupgrade.bin  first install via U-Boot, later upgrades via LuCI/sysupgrade"
echo "  bin/targets/octeon/generic/packages/  every kernel module, built for this exact kernel"
