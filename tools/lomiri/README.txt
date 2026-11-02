Lomiri on the Nexus 5X panel (Ubuntu 26.04 NBD root).
Everything (shell, keyboard, apps) runs on the A418 Mesa in /opt/mesa-a418,
rendering straight to RAM (FD_MESA_DEBUG=sysmem). That Mesa is built with
-Dglvnd=enabled (tools/mesa/build-on-phone.sh): a GLVND vendor (libEGL_mesa,
libGLX_mesa) found first through LD_LIBRARY_PATH, so Qt 5 (libGL) and Qt 6
(libOpenGL + libEGL from GLVND) apps both use it. A non-GLVND build replaced
libEGL.so.1 and crashed Qt 6 apps on their first GL call.

lomiri-phone.service   /etc/systemd/system: Lomiri as user nexus on tty1 (a
                       logind seat: DRM and input devices)
lomiri-gpu.conf        /etc/systemd/user/lomiri.service.d/gpu.conf: the shell
                       on the A418 Mesa, plus QSG_NO_DEPTH_BUFFER=1 (below)
keyboard-gpu.conf      /etc/systemd/user/lomiri-keyboard.service.d/gpu.conf:
                       the on-screen keyboard on the A418 Mesa
bullhead.yaml          /etc/deviceinfo/devices: phone, GridUnit 21
00.edid                /home/nexus/.cache/lomiri/00.edid: the panel's saved
                       display config (a DSI panel has no EDID: "00"), scale 1
ShellScreen.qml        /usr/share/lomiri/ShellScreen.qml (dpkg-divert --local,
                       original in ShellScreen.qml.distrib): the shell's grid
                       unit from GRID_UNIT_PX (internalGu)
zram-swap.service      /etc/systemd/system: 1 GiB zram swap
memlog.sh              memory/GPU trail every 2 s to /var/log/memlog.txt
also: polkitd installed (accounts-daemon needs it; without it Lomiri cannot
read or save its settings), the edge tutorial marked done (AccountsService
com.lomiri.shell.AccountsService demo-edges/DemoEdges2 false).

What was wrong, and why:
- Scale: qtmir sets the output scale to GRID_UNIT_PX / 8 for a DSI panel, and
  Lomiri keeps it per display in ~/.cache/lomiri/<EDID>.edid. Mir 2.25 hands
  that scale on to Wayland clients (wl_output.scale 3, fractional 2.625), but
  Lomiri sizes windows in pixels: apps drew 2.6-3x too big. So the output
  scale stays 1 and the shell's units come from GRID_UNIT_PX.
- Opaque apps invisible full screen (Settings, Qt Quick apps; Terminal with
  its alpha channel was fine): the shell's output surface has no usable depth
  buffer, and Qt's scene graph draws opaque items front to back relying on it:
  the wallpaper behind ended up over them. QSG_NO_DEPTH_BUFFER=1 draws back to
  front. Stock qtmir; no patch needed.

roadfighter-qml.desktop / .svg   ~/.local/share/applications, ~/.local/share/icons:
                       the Road Fighter QML game, pinned in the launcher
                       (gsettings com.lomiri.Shell.Launcher items)
