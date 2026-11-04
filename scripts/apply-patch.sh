#!/usr/bin/env bash
#
# apply-patch.sh — Apply the Linux 7.4 DRM fbdev helper patch to an
#                   extracted NVIDIA open-gpu-kernel-modules source tree.
#
# Usage:
#   ./scripts/apply-patch.sh [DRIVER_SOURCE_DIR]
#
# DRIVER_SOURCE_DIR defaults to $PWD and must point at the directory that
# contains the "nvidia-drm/" subdirectory of the NVIDIA open kernel module
# source (e.g. the kernel-open/ directory extracted from the .run installer).
#
# The script is idempotent: it detects an already-patched tree and exits 0.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATCH_FILE="${REPO_ROOT}/patches/nvidia-595.112.07-linux-7.4-drm-fbdev-helper.patch"
TARGET_DIR="${1:-$PWD}"

DRV_FILE="${TARGET_DIR}/nvidia-drm/nvidia-drm-drv.c"
OLD_INCLUDE='#include <drm/drm_fb_helper.h>'
NEW_INCLUDE='#include <drm/clients/drm_fbdev_helper.h>'

if [[ ! -f "${PATCH_FILE}" ]]; then
    echo "ERROR: patch file not found: ${PATCH_FILE}" >&2
    exit 1
fi

if [[ ! -f "${DRV_FILE}" ]]; then
    echo "ERROR: target file not found: ${DRV_FILE}" >&2
    echo "       Pass the directory that contains 'nvidia-drm/nvidia-drm-drv.c'." >&2
    exit 1
fi

if grep -qF "${NEW_INCLUDE}" "${DRV_FILE}"; then
    echo "OK: patch already applied in ${DRV_FILE}"
    exit 0
fi

if ! grep -qF "${OLD_INCLUDE}" "${DRV_FILE}"; then
    echo "ERROR: expected line not found in ${DRV_FILE}:" >&2
    echo "       ${OLD_INCLUDE}" >&2
    echo "       The tree may be a different driver version; this patch targets 595.112.07." >&2
    exit 1
fi

echo "Applying patch to ${DRV_FILE} ..."
patch -p1 -d "${TARGET_DIR}" < "${PATCH_FILE}"

if grep -qF "${NEW_INCLUDE}" "${DRV_FILE}"; then
    echo "OK: patch applied successfully."
else
    echo "ERROR: patch did not take effect." >&2
    exit 1
fi
