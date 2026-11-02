#!/bin/bash
# build-on-phone.sh: Mesa 26.0.3 (Ubuntu 26.04's version) with
# patches-mesa/*.patch, built on the phone's Ubuntu (NBD root) and installed
# to /opt/mesa-a418, next to the system Mesa, not over it. Only freedreno: no
# LLVM, no Vulkan, as a GLVND vendor (libEGL_mesa, libGLX_mesa: programs pick it up through LD_LIBRARY_PATH, tools/mesa/env.sh).
# Needs the build packages installed and downloads/mesa/mesa-26.0.3.tar.xz.
# The build runs detached on the phone; its log is /root/mesa-build.log.
set -euo pipefail
TOP=$(cd "$(dirname "$0")/../.." && pwd)
SSH="$TOP/tools/ubuntu/ssh-phone.sh"
V=26.0.3
TAR=$TOP/downloads/mesa/mesa-$V.tar.xz
# Ubuntu's mesa_26.0.3.orig.tar.xz (mesa_26.0.3-1ubuntu1.dsc), the same file
echo "ddb7443d328e89aa45b4b6b80f077bf937f099daeca8ba48cabe32aab769e134  $TAR" | sha256sum -c

"$SSH" "rm -rf /root/mesa-$V && tar xJf - -C /root" < "$TAR"
cat "$TOP"/patches-mesa/*.patch | "$SSH" "cd /root/mesa-$V && patch -p1"
# 1.8 GiB of RAM: the VNC desktop stops for the build, and the NIR
# algebraic generator (a big Python run) goes alone, or the OOM killer takes it
"$SSH" "systemctl stop novnc xfce-vnc 2>/dev/null; cd /root/mesa-$V && setsid sh -c '
	meson setup build --prefix=/opt/mesa-a418 --buildtype=release \
		-Dgallium-drivers=freedreno -Dvulkan-drivers= -Dllvm=disabled \
		-Dplatforms=x11,wayland -Degl=enabled -Dgbm=enabled -Dglx=dri \
		-Dglvnd=enabled -Dgles1=disabled -Dgles2=enabled \
		-Dvideo-codecs= -Dbuild-tests=false &&
	ninja -C build -j1 src/compiler/nir/nir_opt_algebraic.c &&
	ninja -C build -j3 && ninja -C build install && echo MESA_BUILD_OK
' > /root/mesa-build.log 2>&1 < /dev/null &" </dev/null
echo "building on the phone: tools/ubuntu/ssh-phone.sh tail /root/mesa-build.log"
