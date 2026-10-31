#!/bin/bash
# Make src/linux-6.12.112-bullhead: the pristine kernel.org tarball plus
# patches/*.patch, as a throwaway git tree (src/linux-6.12.112 stays pristine).
# Re-running it resets the tree to the tarball and applies the series again.
set -euo pipefail
TOP=$(cd "$(dirname "$0")/.." && pwd)
VER=6.12.112
TREE=$TOP/src/linux-$VER-bullhead
GIT=(git -C "$TREE" -c user.name=bullhead-linux -c user.email=bullhead-linux@localhost)

if [ ! -d "$TREE/.git" ]; then
	rm -rf "$TREE" "$TOP/src/linux-$VER-tmp"
	mkdir -p "$TOP/src/linux-$VER-tmp"
	tar xf "$TOP/downloads/linux-$VER.tar.xz" -C "$TOP/src/linux-$VER-tmp"
	mv "$TOP/src/linux-$VER-tmp/linux-$VER" "$TREE"
	rmdir "$TOP/src/linux-$VER-tmp"
	"${GIT[@]}" init -q
	"${GIT[@]}" add -A
	"${GIT[@]}" commit -q -m "linux-$VER"
	"${GIT[@]}" tag base
fi

"${GIT[@]}" am --abort 2>/dev/null || true
"${GIT[@]}" reset -q --hard base
"${GIT[@]}" clean -qfd
"${GIT[@]}" am -q "$TOP"/patches/*.patch
"${GIT[@]}" log --oneline base..HEAD
