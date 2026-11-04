#!/usr/bin/env bash
#
# build-nvidia-740.sh — Build the NVIDIA open GPU kernel modules against a
#                        Linux 7.4.0-rc1 kernel tree.
#
# Usage:
#   ./scripts/build-nvidia-740.sh \
#       --driver-src <extracted-kernel-open-dir> \
#       --kernel-src <linux-7.4-source-dir> \
#       --kernel-out <linux-7.4-build-dir> \
#       [--jobs N]
#
# Example:
#   ./scripts/build-nvidia-740.sh \
#       --driver-src ~/nvidia-595.112.07-extract/kernel-open \
#       --kernel-src ~/linux-7.4-rc1 \
#       --kernel-out ~/linux-7.4-rc1-build \
#       --jobs "$(nproc)"
#
# The script applies the patch automatically (see scripts/apply-patch.sh) and
# then invokes the driver's own Makefile wrapper with SYSSRC/SYSOUT pointing at
# the 7.4 kernel source and output trees.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DRIVER_SRC=""
KERNEL_SRC=""
KERNEL_OUT=""
JOBS="$(nproc)"

usage() {
    cat <<'EOF'
Usage: build-nvidia-740.sh --driver-src DIR --kernel-src DIR --kernel-out DIR [--jobs N]
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --driver-src) DRIVER_SRC="$2"; shift 2 ;;
        --kernel-src) KERNEL_SRC="$2"; shift 2 ;;
        --kernel-out) KERNEL_OUT="$2"; shift 2 ;;
        --jobs)       JOBS="$2";       shift 2 ;;
        -h|--help)    usage ;;
        *) echo "Unknown argument: $1" >&2; usage ;;
    esac
done

[[ -n "${DRIVER_SRC}" && -n "${KERNEL_SRC}" && -n "${KERNEL_OUT}" ]] || usage

for d in "${DRIVER_SRC}" "${KERNEL_SRC}" "${KERNEL_OUT}"; do
    if [[ ! -d "${d}" ]]; then
        echo "ERROR: directory not found: ${d}" >&2
        exit 1
    fi
done

if [[ ! -f "${KERNEL_OUT}/include/generated/utsrelease.h" ]]; then
    echo "ERROR: ${KERNEL_OUT} does not look like a prepared kernel build tree" >&2
    echo "       Run 'make O=<kernel-out> olddefconfig' and build the kernel first." >&2
    exit 1
fi

KERNEL_RELEASE="$(sed -n 's/^#define UTS_RELEASE "\(.*\)"/\1/p' \
    "${KERNEL_OUT}/include/generated/utsrelease.h")"

if [[ -z "${KERNEL_RELEASE}" ]]; then
    echo "ERROR: could not determine UTS_RELEASE from ${KERNEL_OUT}" >&2
    exit 1
fi

echo "==> Kernel release : ${KERNEL_RELEASE}"
echo "==> Driver source  : ${DRIVER_SRC}"
echo "==> Kernel source  : ${KERNEL_SRC}"
echo "==> Kernel output  : ${KERNEL_OUT}"
echo "==> Parallel jobs  : ${JOBS}"
echo

# Work on a writable copy: the extracted installer tree may live on a
# read-only mount and we must not mutate the pristine source.
BUILD_DIR="${DRIVER_SRC}-build"
if [[ ! -d "${BUILD_DIR}" ]]; then
    echo "==> Creating build copy at ${BUILD_DIR}"
    mkdir -p "${BUILD_DIR}"
    cp -a "${DRIVER_SRC}/." "${BUILD_DIR}/"
fi

echo "==> Applying DRM fbdev helper patch"
"${REPO_ROOT}/scripts/apply-patch.sh" "${BUILD_DIR}"
echo

echo "==> Building modules"
make -C "${BUILD_DIR}" -j"${JOBS}" \
    SYSSRC="${KERNEL_SRC}" \
    SYSOUT="${KERNEL_OUT}" \
    modules

echo
echo "==> Built modules:"
find "${BUILD_DIR}" -maxdepth 1 -name '*.ko' -printf '  %-24f %10s bytes\n' | sort
echo
echo "==> Vermagic:"
for ko in "${BUILD_DIR}"/*.ko; do
    printf '  %-24s %s\n' "$(basename "${ko}")" "$(modinfo -F vermagic "${ko}")"
done
echo
echo "Done. Modules are in ${BUILD_DIR}"
