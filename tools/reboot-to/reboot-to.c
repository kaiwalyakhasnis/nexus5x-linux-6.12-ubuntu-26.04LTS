// SPDX-License-Identifier: GPL-2.0
/*
 * reboot-to [bootloader|recovery]: restart with a reason, like Android's
 * "reboot bootloader". BusyBox's reboot cannot pass one. The kernel's
 * qcom-pon reboot-mode driver writes it to the PMIC (PON_SOFT_RB_SPARE),
 * where LK reads it: bootloader = fastboot mode.
 */
#include <linux/reboot.h>
#include <stdio.h>
#include <sys/syscall.h>
#include <unistd.h>

int main(int argc, char **argv)
{
	sync();
	if (argc > 1)
		syscall(SYS_reboot, LINUX_REBOOT_MAGIC1, LINUX_REBOOT_MAGIC2,
			LINUX_REBOOT_CMD_RESTART2, argv[1]);
	else
		syscall(SYS_reboot, LINUX_REBOOT_MAGIC1, LINUX_REBOOT_MAGIC2,
			LINUX_REBOOT_CMD_RESTART, NULL);
	perror("reboot");
	return 1;
}
