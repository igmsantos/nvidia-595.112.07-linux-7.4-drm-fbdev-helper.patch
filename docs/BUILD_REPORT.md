# Build Report — NVIDIA 595.112.07 on Linux 7.4.0-rc1

**Date:** 2026-11-04
**Kernel source:** `https://git.kernel.org/torvalds/t/linux-7.4-rc1.tar.gz` (274,363,544 bytes)
**Kernel source tree:** `~/linux-7.4-rc1`
**Kernel build tree:** `~/linux-7.4-rc1-build` (separate `O=` directory)
**Driver source:** `NVIDIA-Linux-x86_64-595.112.07.run` → `~/nvidia-595.112.07-extract/kernel-open/`
**Driver build tree:** `~/nvidia-595.112.07-build`
**Reference host:** Ubuntu 24.04.4 LTS, Intel Xeon E5-2680 v4, NVIDIA RTX 3060 Ti

---

## 1. Kernel artifacts

| Artifact | Size | Timestamp |
|---|---|---|
| `arch/x86/boot/bzImage` | 15,406,592 B | 2026-11-04 11:38 |
| `vmlinux` | 56,648,104 B | 2026-11-04 11:38 |
| `System.map` | 9,446,788 B | 2026-11-04 11:38 |
| kernel modules (`.ko`) | **170** | — |

`UTS_RELEASE = 7.4.0-rc1`

Two kernel builds were performed:

| Build | Trigger | Result |
|---|---|---|
| `#1` | Initial migration of the 7.3.1 configuration | OK |
| `#2` | Added the generic framebuffer / console fallback stack | OK |

Both completed with **zero compilation errors**.

---

## 2. Configuration migration (7.3.1 → 7.4.0-rc1)

### Method

```bash
cp ~/linux-7.3.1-build/.config ~/linux-7.4-rc1-build/.config
make -C ~/linux-7.4-rc1 O=~/linux-7.4-rc1-build olddefconfig
```

### Diff summary

- Symbols present in both trees: **5,116**
- Total differing config lines: **76**
- Symbols removed by the kernel: **23**
- Symbols added by the kernel: new in 7.4

### Removed symbols that had been enabled

| Symbol | 7.3.1 value | 7.4 status | Impact |
|---|---|---|---|
| `PER_VMA_LOCK` | `=y` | Removed from the tree. Only `PER_VMA_LOCK_STATS` (a `/proc/vmstat` counter) remains — the locking feature itself is gone from the kernel. | Per-VMA locking is lost. Relevant to fine-grained BPF and Landlock-style isolation. |
| `DEBUG_WX` | `=y` | Superseded by `CHECK_WX` (`=y`), enabled via `ARCH_HAS_CHECK_WX`. | **Improvement** — `CHECK_WX` is the stricter successor. |
| `PHYLINK` | `=m` | Became a prompt-less internal symbol → `=y` built-in. | **Improvement** — no longer a loadable module. |

The remaining 20 removed symbols were unset in the 7.3.1 configuration and
therefore had no effect:

`ANDROID_BINDER_IPC`, `ARCH_HAS_DEBUG_WX`, `ARCH_SUPPORTS_PER_VMA_LOCK`,
`ARCH_WANT_HUGETLB_VMEMMAP_PREINIT`, `BFS_FS`, `CRYPTO_XTS`, `HAVE_PREEMPT_DYNAMIC`,
`HAVE_PREEMPT_DYNAMIC_CALL`, `HID_KYSONA`, `LLC2`, `MMU_GATHER_RCU_TABLE_FREE`,
`MMU_GATHER_TABLE_FREE`, `MOXA_INTELLIO`, `QCOM_PAS`, `QCOM_SCM`, `RUSTC_HAS_SPAN_FILE`,
`SATA_INIC162X`, `SPARSEMEM_VMEMMAP_PREINIT`, `TEST_BPF`.

> **False alarm investigated and dismissed:** `LANDLOCK` and `FS_VERITY` appeared
> to be missing in the 7.4 configuration. Cross-checking the 7.3.1 reference
> showed they were **never enabled** there either — the migration did not drop
> them.

### Symbols newly introduced in 7.4

| Symbol | Value | Notes |
|---|---|---|
| `BPF_CRYPTO` | `=y` | BPF programs can use kernel crypto primitives |
| `RCU_DEFER` | `=y` | Deferred RCU callbacks |
| `VMEMMAP_OPTIMIZATION` | `=y` | Optimized virtual memory map |
| `PNFS_SCSI_LAYOUT` | `=y` | pNFS over SCSI |
| `CRYPTO_LIB_AES_XTS` | `=y` | AES-XTS cipher library |
| `CHECK_WX` | `=y` | Strict W^X enforcement (replaces `DEBUG_WX`) |

---

## 3. Framebuffer / console fallback stack

Added in kernel build `#2` in response to the explicit requirement that the
machine must never boot without video output.

### Problem

Linux 7.4 reworked the DRM fbdev subsystem. `include/drm/drm_fb_helper.h` was
removed and the API moved to `include/drm/clients/drm_fbdev_helper.h`. The
configuration therefore had to be re-verified from scratch against the 7.4
source tree rather than inherited.

### Symbols enabled and verified in `.config`

**Legacy framebuffer core**

```
CONFIG_FB=y
CONFIG_FB_CORE=y
CONFIG_FB_NOTIFY=y
CONFIG_FB_DEVICE=y
CONFIG_FB_SYSMEM_FOPS=y
CONFIG_FB_SYSMEM_HELPERS=y
CONFIG_FB_SYSMEM_HELPERS_DEFERRED=y
CONFIG_FB_IOMEM_FOPS=y
CONFIG_FB_IOMEM_HELPERS=y
CONFIG_FB_CFB_FILLRECT=y
CONFIG_FB_CFB_COPYAREA=y
CONFIG_FB_CFB_IMAGEBLIT=y
CONFIG_FB_DEFERRED_IO=y
```

**Generic framebuffer drivers**

```
CONFIG_FB_VESA=y
CONFIG_FB_EFI=y
CONFIG_SYSFB=y
CONFIG_SYSFB_SIMPLEFB=y
CONFIG_DRM_SYSFB_HELPER=y
CONFIG_DRM_SIMPLEDRM=y
CONFIG_DRM_BOCHS=y
CONFIG_DRM_QXL=y
CONFIG_DRM_VIRTIO_GPU=y
```

**Console**

```
CONFIG_VT=y
CONFIG_VT_CONSOLE=y
CONFIG_VT_CONSOLE_SLEEP=y
CONFIG_FRAMEBUFFER_CONSOLE=y
CONFIG_FRAMEBUFFER_CONSOLE_DETECT_PRIMARY=y
CONFIG_VGA_CONSOLE=y
CONFIG_VGA_ARB=y
CONFIG_DUMMY_CONSOLE=y
CONFIG_DUMMY_CONSOLE_COLUMNS=80
CONFIG_DUMMY_CONSOLE_ROWS=25
CONFIG_EFI=y
CONFIG_EFI_STUB=y
CONFIG_EFI_EARLYCON=y
CONFIG_SERIAL_8250_CONSOLE=y
CONFIG_SERIAL_8250_PCI=y
```

**New DRM client framework (7.4-specific)**

```
CONFIG_DRM_CLIENT=y
CONFIG_DRM_CLIENT_LIB=y
CONFIG_DRM_CLIENT_SELECTION=y
CONFIG_DRM_CLIENT_SETUP=y
CONFIG_DRM_FBDEV_EMULATION=y
CONFIG_DRM_FBDEV_OVERALLOC=100
```

### Mutual-exclusion analysis

`DRM_VESADRM` and `DRM_EFIDRM` were evaluated and intentionally left disabled:

```
config DRM_VESADRM
	tristate "VESA framebuffer driver"
	depends on DRM && MMU && X86 && (!SYSFB_SIMPLEFB || COMPILE_TEST)
```

They are mutually exclusive with `SYSFB_SIMPLEFB`. Enabling `SYSFB_SIMPLEFB`
covers the VESA and EFI framebuffer cases with a single driver and eliminates
the risk of two drivers contending for the same device. The `COMPILE_TEST`
escape hatch exists only for out-of-tree builds that need to compile against a
kernel with `SYSFB_SIMPLEFB` enabled — it is not a runtime mode.

---

## 4. NVIDIA driver: version escalation

### Why 595.84 could not be used

The `nvidia/595.84` DKMS package installed on the host fails to build against
7.4-rc1 with **seven** errors:

| # | File | Error |
|---|---|---|
| 1 | `nvidia-drm/nvidia-drm-drv.c:67` | `fatal error: drm/drm_fb_helper.h: No such file or directory` |
| 2 | `nvidia-drm/nvidia-drm-crtc.c:2091` | `struct drm_plane_funcs` has no member `reset` — incompatible pointer type |
| 3 | `nvidia-drm/nvidia-drm-crtc.c:2192` | implicit declaration of `drm_atomic_helper_crtc_reset` |
| 4 | `nvidia-drm/nvidia-drm-crtc.c:2301` | `struct drm_crtc_funcs` has no member `reset` |
| 5–7 | `nvidia-drm/nvidia-drm-crtc.c` | related `drm_atomic_helper_plane_reset` / pointer-type diagnostics |

### Root cause

Linux 7.4 removed the `reset` callback from `struct drm_plane_funcs` and
`struct drm_crtc_funcs` in favour of:

```c
struct drm_plane_state *(*atomic_create_state)(struct drm_plane *plane);
struct drm_crtc_state  *(*atomic_create_state)(struct drm_crtc *crtc);
```

and dropped the corresponding `drm_atomic_helper_plane_reset()` /
`drm_atomic_helper_crtc_reset()` helpers. `595.84` predates that rework.

### Escalation to 595.112.07

| | |
|---|---|
| Release date | 2026-10-22 |
| Installer | `https://us.download.nvidia.com/XFree86/Linux-x86_64/595.112.07/NVIDIA-Linux-x86_64-595.112.07.run` |
| Size | 423,351,953 bytes |
| Extraction | `sh NVIDIA-595.112.07.run --extract-only --target ~/nvidia-595.112.07-extract` |
| Source tree | `~/nvidia-595.112.07-extract/kernel-open/` |

`595.112.07` already implements the new atomic-state API. The six `reset`-related
errors disappeared **without any modification**. Only the header include
remained.

---

## 5. The patch

### Change

`nvidia-drm/nvidia-drm-drv.c`, line 67:

```diff
--- a/nvidia-drm/nvidia-drm-drv.c
+++ b/nvidia-drm/nvidia-drm-drv.c
@@ -64,7 +64,7 @@
 #endif

 #if defined(NV_DRM_FBDEV_AVAILABLE)
-#include <drm/drm_fb_helper.h>
+#include <drm/clients/drm_fbdev_helper.h>
 #endif

 #if defined(NV_DRM_DRM_CLIENT_SETUP_H_PRESENT)
```

### Verification that the API is preserved

The function used by the driver still exists in 7.4 with an unchanged signature:

```c
/* include/drm/clients/drm_fbdev_helper.h:264 */
void drm_fb_helper_set_suspend_unlocked(struct drm_fb_helper *fb_helper,
					bool suspend);
```

The two call sites in `nv_drm_suspend_resume()` therefore need no changes:

```c
#if defined(NV_DRM_FBDEV_AVAILABLE)
        drm_fb_helper_set_suspend_unlocked(dev->fb_helper, 1);
#endif
```

`struct drm_device` still carries the `fb_helper` member
(`include/drm/drm_device.h:371`).

### Patch validation

```
$ git apply --check -v nvidia-595.112.07-linux-7.4-drm-fbdev-helper.patch
Checking patch nvidia-drm/nvidia-drm-drv.c...
EXIT:0

$ patch -p1 --dry-run < nvidia-595.112.07-linux-7.4-drm-fbdev-helper.patch
checking file nvidia-drm/nvidia-drm-drv.c
EXIT:0
```

The patch was generated with `diff -u` against the pristine upstream file
(preserved at `~/linux-kernel-ai/reports/backups/nvidia-595112-nvidia-drm-drv.c.orig`)
rather than hand-written, guaranteeing it applies cleanly.

---

## 6. Build result

### Command

```bash
cd ~/nvidia-595.112.07-build && make -j"$(nproc)" \
    SYSSRC=/home/ivan/linux-7.4-rc1 \
    SYSOUT=/home/ivan/linux-7.4-rc1-build \
    modules
```

### Errors

```
$ grep -cE 'error:' build.log
0
```

### Modules produced

| Module | Size | vermagic |
|---|---|---|
| `nvidia.ko` | 25,060,768 B | `7.4.0-rc1 SMP preempt mod_unload` |
| `nvidia-modeset.ko` | 4,033,576 B | `7.4.0-rc1 SMP preempt mod_unload` |
| `nvidia-drm.ko` | 273,552 B | `7.4.0-rc1 SMP preempt mod_unload` |
| `nvidia-uvm.ko` | 3,614,128 B | `7.4.0-rc1 SMP preempt mod_unload` |
| `nvidia-peermem.ko` | 7,536 B | `7.4.0-rc1 SMP preempt mod_unload` |

### Module metadata

```
version:      595.112.07
license:      Dual MIT/GPL
srcversion:   7931BAB479A0521EACA5428
vermagic:     7.4.0-rc1 SMP preempt mod_unload
firmware:     nvidia/595.112.07/gsp_tu10x.bin
description:  NVIDIA core GPU kernel module
```

### Non-fatal warnings

`objtool` emits `'naked' return found in MITIGATION_RETHUNK build` warnings for
many NVIDIA functions. These are inherent to the driver's use of the
retpoline mitigation and do not affect the build result.

---

## 7. Build environment

| Item | Value |
|---|---|
| Kernel source | `~/linux-7.4-rc1` |
| Kernel output | `~/linux-7.4-rc1-build` |
| Driver source | `~/nvidia-595.112.07-extract/kernel-open/` |
| Driver output | `~/nvidia-595.112.07-build` |
| Disk space at start | 74 GB free on `/` |
| Compiler | system GCC |

---

## 8. Incident referenced by the troubleshooting section

During the 7.3.1 work, a boot failed with:

```
BUG: unable to handle page fault for address: 0000000043e5fbc4
#PF: supervisor read access in kernel mode
```

The root cause was **not** a kernel bug: `/lib/modules/7.3.1` contained only 68
modules from an older build while the current build produced 172, and
`modules_install` had removed the NVIDIA modules from the tree because they are
not part of the kernel build. The system booted with a mismatched module set and
a stale `cfg80211.ko`.

This is why `scripts/verify-build.sh` checks the `vermagic` of every module and
why `scripts/install-modules.sh` always re-copies the NVIDIA modules and
regenerates the initramfs after `modules_install`.

---

## 9. Outstanding steps (require root)

The agent running this build has no sudo access; these are executed by the
operator:

```bash
sudo ./scripts/install-modules.sh \
    --kernel-src ~/linux-7.4-rc1 \
    --kernel-out ~/linux-7.4-rc1-build \
    --driver-build ~/nvidia-595.112.07-build
```

Then reboot manually.

> The `nvidia/595.84` DKMS package on the host is **not** usable with 7.4.
> Either register `595.112.07` with DKMS (see the README) or rely on the manual
> module copy performed by `install-modules.sh`.
