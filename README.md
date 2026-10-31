# Nexus 5X on Linux 6.12 + BusyBox (WIP)

> **Disclaimer.** This is an experiment: I'm trying out what Claude can do
> with an old phone. Most of the patches, device tree and text were written
> with Claude. They did boot on one Nexus 5X, but they may be
> wrong, unsafe or complete garbage. Nothing here has been reviewed by anyone
> who knows these drivers. Read it as notes from an experiment, not a reference,
> and use it at your own risk (`fastboot boot` only, never flash it).

> **Work in progress.** Display, all 6 cores and CPU frequency scaling work; much of the phone does not yet (see the table below).

The LG Nexus 5X (bullhead, Snapdragon 808 / MSM8992) running a kernel.org
6.12 LTS kernel (plain upstream stable, not Android's ACK/GKI) with a static
BusyBox userspace. It has the real MDP5/DSI display driver, all 6 CPU cores and
CPU frequency scaling up to the stock 1.44/1.82 GHz.
Nothing gets flashed: `fastboot boot` loads it into RAM, and a reboot goes
back to whatever is installed.

| Status screen (tty1) | BusyBox shell on the panel | `cat /proc/cpuinfo` | `top`, per-core view (`1`) |
|:---:|:---:|:---:|:---:|
| <img src="screenshots/status.png" width="260"> | <img src="screenshots/shell.png" width="260"> | <img src="screenshots/cpuinfo.png" width="260"> | <img src="screenshots/top.png" width="260"> |

The screenshots are copied straight from `/dev/fb0` on the phone (`cat /dev/fb0 | nc`).
The trace on the status screen is a harmless backlight-driver warning (see below).
Tested on a rev_1.0 board (LGH791, bootloader BHZ32c).

## What works and what doesn't

| | Part | Notes |
|---|---|---|
| ✅ | Boot with `fastboot boot` (RAM only) | Image 26 MiB, under the bootloader's ~29.5 MiB limit |
| ✅ | 4 × Cortex-A53 (CPU0-3) | 384-1440 MHz (stock speed bin 1 table), schedutil |
| ✅ | 2 × Cortex-A57 (CPU4-5) | 384-1824 MHz (stock speed bin 0 table), schedutil. They join late with `arm64.late_cpu_conflicts=warn`, so they run without their Spectre-v2 mitigation and A57 errata workarounds (832075 can rarely hang the CPU) |
| ✅ | Display: MDP5 1.10 + DSI + JD35695B panel driver | Framebuffer console with a 16×32 font (67×60 characters) |
| ✅ | Backlight (PMI8994 WLED) | Stock limits: 15 mA per string, 29.5 V OVP |
| ✅ | USB network (NCM) + telnet | `telnet 172.16.42.1`. `conspy 2` lets you type into the shell on the panel |
| ✅ | eMMC detected, pstore/ramoops, QEMU `virt` | eMMC is never mounted or written |
| ✅ | Temperature sensors (TSENS) | 13 thermal zones in `/sys/class/thermal`, calibrated from the phone's fuses. Each shuts the phone down at 115 °C, the stock reset temperature |
| ✅ | CPU voltages (CPR open loop) | Per-speed voltages from the chip's own fuses, computed like 3.10's `cpr-regulator`, within the stock floor and ceiling. The MX memory rail is voted per speed, and the A53 rail stays high enough for the CCI |
| ⚠️ | Thermal throttling | Configured with the stock limits from 3.10's `msm_thermal`: all CPUs slow down from 60 °C, the A57s are capped at 768 MHz from 100 °C. Not yet seen to trigger (load tests peak near 49 °C) |
| ✅ | Reboot, and reboot to fastboot | `reboot-to bootloader` on the phone, or `scripts/phone-boot.sh` from the PC, gets to LK's fastboot with no buttons |
| ⚠️ | Display on every boot | About 1 boot in 6 the RPM (SMD) does not answer. Then there are no RPM regulators: the panel stays frozen on the bootloader's Google logo and cpufreq stays off (telnet still works). A `reboot` from such a boot can hang: hold Power, then Power + Volume down |
| ⚠️ | Boot-time `WARNING` from `wled_ovp_work` | An unbalanced `enable_irq`, because the bootloader leaves the backlight on. Cosmetic |
| ❌ | Closed-loop CPR, thermal core control | The CPR hardware loop that trims voltage below open loop (stock runs 1440 MHz at 1115 mV, here 1160 mV). The stock 80 °C core offlining has no mainline equivalent |
| ❌ | GPU (Adreno 418), IOMMU | Scanout uses a contiguous carveout instead |
| ❌ | Touch, Wi-Fi/BT, modem, audio, camera, sensors, battery/charging | Not attempted |

## The hacks it takes

Mainline already has a bullhead device tree, but on its own that only reaches
a shell on CPU0. These are the extra pieces:

1. **No PSCI in the firmware**, so mainline can't start the other cores.
   Patches 0001, 0003, 0008 and 0009 bring them up the 3.10 way instead (the
   `qcom,8994-arm-cortex-acc` method):
   * The cold-boot address is handed to TrustZone over SCM, in AArch64 state.
   * Each core's ACC power, clamps and reset are released.
   * For the A57s, the cluster L2 is powered up first. Their clock mux is set to
     GPLL0 (600 MHz) before that (0008), as 3.10's
     `cpu_clock_8994_init_a57_v2()` does; the bootloader leaves it on the
     19.2 MHz reference.
   * SCM isn't ready at `smp_init`, so CPU1-5 come online at `late_initcall`.
     The system's CPU capabilities were already decided by the A53s, so
     mainline would refuse the A57s. 0009 adds `arm64.late_cpu_conflicts=warn`
     to let them in without those mitigations. Starting the cores from
     `smp_init` instead (with an early SCM call) made the RPM link fail on
     every boot.
2. **No 20nm DSI PLL driver**, so the display PLL the bootloader (LK) left
   running is kept as it is:
   * 0002 keeps the MDSS power domain on.
   * 0004 stops the PHY from being reset.
   * The device tree describes the PLL outputs as fixed clocks: 148.684 MHz
     pixel, 111.513 MHz byte.
3. **The MSM8992 is not the MSM8994.**
   * 0005 adds the 8992's DSI and PHY addresses.
   * 0006 adds a configuration table for MDP 1.10, since mainline only knew 1.9.
4. **A panel driver** (0007) for the JD35695B command-mode panel:
   * L22/L25 supplies, the DW8768 ±5.5 V enables (GPIO 89/90) and reset (GPIO 78);
   * one of LK's three gamma tables, chosen from LK's command line;
   * the 3.10 init commands.
5. **No IOMMU**, so the display scans out of a contiguous carveout
   (`msm.vram=32m cma=96M`).
6. **Command line**: `clk_ignore_unused pd_ignore_unused regulator_ignore_unused`
   so nothing the bootloader set up gets switched off,
   `fbcon=font:TER16x32` so the console is readable on a 1080-pixel panel, and
   `arm64.late_cpu_conflicts=warn` for the A57s.
7. **Device tree values**: the WLED OVP comes from the PMI8994 table (29.5 V),
   and the DSI supplies (L2, L12, L28) come from the 3.10 dtsi.
8. **Size diet** (`scripts/kernel.config`): everything is built in and there
   are no modules, so the image fits the bootloader's load window.
9. **TSENS** (0010): the 8992's sensor block is TSENS v1 with 16 sensors, 13 of
   them used. Its calibration fuses are decoded as in 3.10's
   `tsens_calib_8992_sensors()`.
10. **Reboot**: `qcom-pon` must be built in. Its child power-key driver sets
    the PMIC to reset, not power off, when the kernel releases PS_HOLD. LK reads
    the reboot reason in LG's own encoding (bits swapped, shifted by 1), so the
    DT sets `mode-bootloader = <0x10>` and `mode-recovery = <0x8>`. BusyBox's
    `reboot` can't pass a reason, so `tools/reboot-to` does.
11. **CPU clocks** (0011): no mainline driver, so a small one after 3.10's
    `clock-cpu-8994.c`. To change speed it parks the cluster on GPLL0
    (600 MHz) and reprograms the cluster PLL with the 3.10 lock sequence. It
    then selects the PLL directly (from 1209.6 MHz) or through its /2 or /4
    divider. The CCI clock is only read, through SCM like 3.10, and stays at
    the bootloader's 300 MHz.
12. **CPU voltages** (0012): the open-loop part of 3.10's `cpr-regulator`.
    It reads the speed bin, CPR fuse revision, ring-oscillator selects and
    fused per-corner voltages. It applies the version-map adjustments,
    interpolates between fuse corners and clamps to the stock floor/ceiling
    overrides. Then it writes the result into the CPU OPP tables and starts
    cpufreq-dt itself. The OPPs also vote the MX corner (`required-opps`),
    and the A53 rail never drops below the CCI's corner. Every value was
    checked against the stock driver's own log on the same phone.
    `dts/bullhead-cpr.dtsi` is generated from the 3.10 DT by
    `tools/cpr/gen-cpr-dtsi.py`.

Patches 0001-0004 and 0009 come from
[oneplus2-mainline](https://github.com/luvingiane/oneplus2-mainline)
(OnePlus 2, MSM8994, GPL-2.0). Each value was checked against the Nexus 5X's
own 3.10 kernel source. Patches 0005-0008 and 0010-0012 are new.

## Build and boot

```sh
sudo apt install gcc-aarch64-linux-gnu qemu-system-arm bc flex bison libssl-dev
scripts/fetch-sources.sh       # Linux 6.12.112 + BusyBox 1.36.1 into downloads/, src/
scripts/build-kernel.sh        # applies patches/ onto a copy of the tarball, then builds
scripts/build-busybox.sh
scripts/build-initramfs.sh
scripts/build-bootimg.sh       # out/boot-rev-{10,101}.img and -keep.img variants

scripts/run-qemu.sh            # optional: the same kernel + initramfs on QEMU virt

fastboot getvar version-hardware   # rev_1.0 -> rev-10, rev_1.01 -> rev-101
fastboot boot out/boot-rev-10.img  # RAM only, nothing is written
telnet 172.16.42.1                 # PC side gets 172.16.42.2 over DHCP
```

* **Black panel?** Hold Power for 10 s and try `boot-rev-10-keep.img`, which
  keeps LK's panel state instead of re-initialising the panel.
* **Getting back to fastboot:** `reboot-to bootloader` in telnet. Or run
  `scripts/phone-boot.sh [image]`: from this kernel, from Android (adb) or
  from fastboot, it gets to fastboot, boots the image and waits for the USB
  network.

## Layout

| Path | What it is |
|---|---|
| `patches/` | The 12 kernel patches above, applied by `scripts/prepare-kernel.sh` |
| `dts/` | Board files: mainline `msm8992-lg-bullhead`, `bullhead-smp.dtsi` (ACC for CPU1-5, A57 L2 and clock mux), `bullhead-display.dtsi` (MDSS, DSI, panel, WLED), `bullhead-thermal.dtsi` (QFPROM, TSENS, thermal zones), `bullhead-cpufreq.dtsi` (rails, CPU clocks, throttling), `bullhead-cpr.dtsi` (CPR nodes, OPP tables; generated) |
| `scripts/kernel.config` | Options built into the kernel, plus the size diet |
| `rootfs/` | `/init` (mounts, then hands off to BusyBox init), `inittab`, `rcS` (USB gadget, telnetd), status screen, boot report |
| `scripts/mkbootimg.py` | A ~60-line Android boot image writer |
| `tools/gen-jd35695b-gamma.py` | Turns the 3.10 panel gamma tables into the driver's header |
| `tools/cpr/` | `cpr_open_loop.py` (the open-loop voltages from a fuse dump, to check against) and `gen-cpr-dtsi.py` |
| `tools/reboot-to/` | `reboot-to bootloader\|recovery`: reboot with a reason, built into the initramfs |
| `scripts/phone-boot.sh` | From wherever the phone is, to fastboot, then `fastboot boot` an image |

Kernel patches are GPL-2.0, like the kernel they apply to.
