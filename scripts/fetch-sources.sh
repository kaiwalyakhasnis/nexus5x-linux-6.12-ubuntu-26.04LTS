#!/bin/bash
# Download + unpack pristine upstream sources into src/ (not tracked in git).
set -euo pipefail
TOP=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$TOP/downloads" "$TOP/src"
cd "$TOP/downloads"
[ -f linux-6.12.112.tar.xz ] || curl -fLO https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.12.112.tar.xz
[ -f busybox-1.36.1.tar.bz2 ] || curl -fLO https://busybox.net/downloads/busybox-1.36.1.tar.bz2
cd "$TOP/src"
[ -d linux-6.12.112 ] || tar xf ../downloads/linux-6.12.112.tar.xz
[ -d busybox-1.36.1 ] || tar xf ../downloads/busybox-1.36.1.tar.bz2
