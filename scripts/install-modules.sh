#!/usr/bin/env bash
#
# install-modules.sh — Install the NVIDIA kernel modules and the 7.4.0-rc1
#                       kernel into the running system.
#
# Usage:
#   sudo ./scripts/install-modules.sh \
#       --kernel-src <linux-7.4-source-dir> \
#       --kernel-out <linux-7.4-build-dir> \
#       --driver-build <nvidia-module-build-dir> \
#       [--kernel-release 7.4.0-rc1]
#
# This script requires root and performs privileged operations:
#   - modules_install into /lib/modules/<release>
#   - copy of the NVIDIA .ko files into the module tree
#   - depmod
#   - initramfs regeneration
#   - kernel image installation into /boot
#   - GRUB configuration refresh
#
# It does NOT reboot. Rebooting is always an explicit, manual decision.

set -euo pipefail

KERNEL_SRC=""
KERNEL_OUT=""
DRIVER_BUILD=""
KERNEL_RELEASE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --kernel-src)    KERNEL_SRC="$2";    shift 2 ;;
        --kernel-out)    KERNEL_OUT="$2";    shift 2 ;;
        --driver-build)  DRIVER_BUILD="$2";  shift 2 ;;
        --kernel-release) KERNEL_RELEASE="$2"; shift 2 ;;
        -h|--help)
            cat <<'EOF'
Usage: install-modules.sh --kernel-src DIR --kernel-out DIR --driver-build DIR [--kernel-release REL]
EOF
            exit 0
            ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

[[ -n "${KERNEL_SRC}" && -n "${KERNEL_OUT}" && -n "${DRIVER_BUILD}" ]] || {
    echo "ERROR: --kernel-src, --kernel-out and --driver-build are required" >&2
    exit 1
}

if [[ "$(id -u)" -ne 0 ]]; then
    echo "ERROR: this script must be run as root (try: sudo $0 ...)" >&2
    exit 1
fi

if [[ -z "${KERNEL_RELEASE}" ]]; then
    KERNEL_RELEASE="$(sed -n 's/^#define UTS_RELEASE "\(.*\)"/\1/p' \
        "${KERNEL_OUT}/include/generated/utsrelease.h")"
fi

if [[ -z "${KERNEL_RELEASE}" ]]; then
    echo "ERROR: could not determine the kernel release" >&2
    exit 1
fi

echo "==> Kernel release: ${KERNEL_RELEASE}"
echo

echo "==> [1/6] modules_install"
make -C "${KERNEL_SRC}" O="${KERNEL_OUT}" modules_install
echo

echo "==> [2/6] Installing NVIDIA modules"
NVIDIA_DEST="/lib/modules/${KERNEL_RELEASE}/kernel/drivers/video/nvidia"
mkdir -p "${NVIDIA_DEST}"
cp -v "${DRIVER_BUILD}"/*.ko "${NVIDIA_DEST}/"
echo

echo "==> [3/6] depmod"
depmod "${KERNEL_RELEASE}"
echo

echo "==> [4/6] Regenerating initramfs (this can take a few minutes — do not interrupt)"
update-initramfs -u -k "${KERNEL_RELEASE}"
echo

echo "==> [5/6] Installing kernel image and modules to /boot"
make -C "${KERNEL_SRC}" O="${KERNEL_OUT}" install
echo

echo "==> [6/6] Refreshing GRUB configuration"
if command -v update-grub > /dev/null 2>&1; then
    update-grub
elif command -v grub-mkconfig > /dev/null 2>&1; then
    grub-mkconfig -o /boot/grub/grub.cfg
else
    echo "WARNING: neither update-grub nor grub-mkconfig found; update the bootloader manually." >&2
fi
echo

echo "=============================================================="
echo " Installation complete for kernel ${KERNEL_RELEASE}"
echo
echo " Verify the boot entries:"
echo "   grep -A3 'menuentry.*${KERNEL_RELEASE}' /boot/grub/grub.cfg"
echo
echo " Reboot when ready (not performed by this script):"
echo "   sudo reboot"
echo "=============================================================="
