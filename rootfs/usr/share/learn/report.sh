#!/bin/sh
echo "=== bullhead-learn boot report ==="
uname -a
tr -d '\0' < /proc/device-tree/model; echo
echo "--- cpus online: $(cat /sys/devices/system/cpu/online)"
grep -E 'MemTotal|MemFree' /proc/meminfo
echo "--- block devices"; cat /proc/partitions
echo "--- drivers bound"; ls /sys/bus/platform/drivers/*/ 2>/dev/null | grep -c '@'
echo "--- failed/deferred probes"; cat /sys/kernel/debug/devices_deferred 2>/dev/null
echo "--- dmesg warnings"; dmesg | grep -iE 'error|fail|warn' | tail -n 40
echo "--- cpu bring-up (ACC, no PSCI)"; dmesg | grep -E 'CPU[0-9]+:|smp|SMP' | tail -n 20
mount -t debugfs debugfs /sys/kernel/debug 2>/dev/null
echo "--- display"; ls /sys/class/drm /sys/class/backlight 2>/dev/null | tr '\n' ' '; echo
cat /proc/fb
dmesg | grep -iE 'msm|mdp|dsi|panel|jd35695b|wled|simple-framebuffer|simpledrm|vram' | tail -n 40
# LK's DSI clocks, before/after msm took over: RCG CMD/CFG/M/N/D (mmcc 0xfd8c0000)
for r in 0xfd8c2000 0xfd8c2004 0xfd8c2008 0xfd8c200c 0xfd8c2010 0xfd8c2120 0xfd8c2124 0xfd8c2040 0xfd8c2044; do
	echo "$r = $(devmem $r 32)"
done
echo "dsi0 phy CTRL_0 = $(devmem 0xfd994670 32) (0x7f: LK left the PHY on)"
grep -E 'byte0|pclk0|mdp_clk|esc0|dsi0pll' /sys/kernel/debug/clk/clk_summary 2>/dev/null
