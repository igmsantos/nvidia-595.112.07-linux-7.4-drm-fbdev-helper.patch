#!/usr/bin/env bash
#
# verify-build.sh — Validate that the NVIDIA modules were built correctly
#                    against the target kernel and that the kernel exposes the
#                    legacy fbdev / framebuffer console stack.
#
# Usage:
#   ./scripts/verify-build.sh --kernel-out DIR [--driver-build DIR]
#
# Exit status: 0 when everything checks out, 1 otherwise.

set -uo pipefail

KERNEL_OUT=""
DRIVER_BUILD=""
FAILURES=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --kernel-out)   KERNEL_OUT="$2";   shift 2 ;;
        --driver-build) DRIVER_BUILD="$2"; shift 2 ;;
        -h|--help)
            cat <<'EOF'
Usage: verify-build.sh --kernel-out DIR [--driver-build DIR]
EOF
            exit 0
            ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

[[ -n "${KERNEL_OUT}" ]] || { echo "ERROR: --kernel-out is required" >&2; exit 1; }
[[ -d "${KERNEL_OUT}" ]] || { echo "ERROR: not a directory: ${KERNEL_OUT}" >&2; exit 1; }

pass() { printf '  [ OK ] %s\n' "$1"; }
fail() { printf '  [FAIL] %s\n' "$1"; FAILURES=$((FAILURES + 1)); }

EXPECTED_RELEASE="$(sed -n 's/^#define UTS_RELEASE "\(.*\)"/\1/p' \
    "${KERNEL_OUT}/include/generated/utsrelease.h" 2>/dev/null)"

echo "=============================================================="
echo " NVIDIA module + framebuffer stack verification"
echo " Kernel release: ${EXPECTED_RELEASE:-unknown}"
echo "=============================================================="
echo

echo "--- NVIDIA modules ---"
if [[ -n "${DRIVER_BUILD}" && -d "${DRIVER_BUILD}" ]]; then
    shopt -s nullglob
    kos=("${DRIVER_BUILD}"/*.ko)
    shopt -u nullglob
    if [[ ${#kos[@]} -eq 0 ]]; then
        fail "no .ko files found in ${DRIVER_BUILD}"
    fi
    for ko in "${kos[@]}"; do
        name="$(basename "${ko}")"
        vm="$(modinfo -F vermagic "${ko}" 2>/dev/null)"
        ver="$(modinfo -F version "${ko}" 2>/dev/null)"
        if [[ "${vm}" == "${EXPECTED_RELEASE}"* ]]; then
            pass "${name} (version ${ver}) — vermagic '${vm}'"
        else
            fail "${name} — vermagic '${vm}' does not match '${EXPECTED_RELEASE}'"
        fi
    done
    for required in nvidia.ko nvidia-modeset.ko nvidia-drm.ko nvidia-uvm.ko; do
        if compgen -G "${DRIVER_BUILD}/${required}" > /dev/null; then
            pass "required module present: ${required}"
        else
            fail "required module missing: ${required}"
        fi
    done
else
    echo "  (skipped: --driver-build not supplied)"
fi
echo

echo "--- Kernel legacy framebuffer / console stack ---"
CONFIG="${KERNEL_OUT}/.config"
if [[ -f "${CONFIG}" ]]; then
    for sym in FB FB_CORE FB_SYSMEM_FOPS FB_SYSMEM_HELPERS FB_IOMEM_FOPS \
               FB_IOMEM_HELPERS FB_VESA FB_EFI SYSFB_SIMPLEFB DRM_SIMPLEDRM \
               DRM_BOCHS DRM_QXL DRM_VIRTIO_GPU DRM_CLIENT_LIB \
               DRM_CLIENT_SELECTION DRM_CLIENT_SETUP DRM_FBDEV_EMULATION \
               FRAMEBUFFER_CONSOLE VT VT_CONSOLE VGA_CONSOLE \
               DUMMY_CONSOLE EFI_STUB EFI_EARLYCON SERIAL_8250_CONSOLE; do
        val="$(grep -E "^CONFIG_${sym}=" "${CONFIG}" | head -1 | cut -d= -f2)"
        if [[ "${val}" == "y" || "${val}" == "m" ]]; then
            pass "CONFIG_${sym}=${val}"
        else
            fail "CONFIG_${sym} is not enabled (value='${val:-unset}')"
        fi
    done
else
    fail "kernel .config not found at ${CONFIG}"
fi
echo

echo "=============================================================="
if [[ ${FAILURES} -eq 0 ]]; then
    echo " RESULT: all checks passed"
    echo "=============================================================="
    exit 0
fi
echo " RESULT: ${FAILURES} check(s) failed"
echo "=============================================================="
exit 1
