# NVIDIA 595.112.07 — Linux 7.4 DRM fbdev helper patch

A single-line patch that lets the **NVIDIA open GPU kernel modules 595.112.07** build
against **Linux 7.4.0-rc1**, together with a complete, hardware-aware kernel
configuration and the supporting build/install/verification tooling.

---

## TL;DR

Linux 7.4 removed `include/drm/drm_fb_helper.h` and moved the legacy fbdev API to
`include/drm/clients/drm_fbdev_helper.h`. The NVIDIA 595.84 driver still includes the
old path and **fails to build**. This repository provides the fix:

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

`drm_fb_helper_set_suspend_unlocked()` still exists in 7.4 with an unchanged
signature — only the include path moved.

| | |
|---|---|
| **Driver** | NVIDIA open GPU kernel modules `595.112.07` (released 2026-10-22) |
| **Kernel** | Linux `7.4.0-rc1` (torvalds/linux, `linux-7.4-rc1.tar.gz`) |
| **Patch size** | 1 line, 1 file |
| **Build result** | 5 modules, **0 errors** |
| **Target hardware** | Intel Xeon E5-2680 v4 (Broadwell-EP) + NVIDIA RTX 3060 Ti (GA104) |

---

## Table of contents

- [Why the patch is needed](#why-the-patch-is-needed)
- [Requirements](#requirements)
- [Quick start](#quick-start)
- [What the patch changes](#what-the-patch-changes)
- [Kernel configuration](#kernel-configuration)
- [Framebuffer / console fallback stack](#framebuffer--console-fallback-stack)
- [Repository layout](#repository-layout)
- [Verification](#verification)
- [Installation](#installation)
- [Troubleshooting](#troubleshooting)
- [References](#references)
- [License](#license)

---

## Why the patch is needed

Linux 7.4 reworked the DRM fbdev subsystem. The `drm_fb_helper` API — including the
public header `include/drm/drm_fb_helper.h` — was relocated under the new
`drm_client` framework:

| Linux ≤ 7.3 | Linux 7.4 |
|---|---|
| `include/drm/drm_fb_helper.h` | `include/drm/clients/drm_fbdev_helper.h` |
| `include/drm/drm_fbdev_dma.h` | `include/drm/drm_fbdev_dma.h` (unchanged) |
| `include/drm/drm_fbdev_shmem.h` | `include/drm/drm_fbdev_shmem.h` (unchanged) |
| — | `include/drm/clients/drm_client_setup.h` (new) |

### Build failure with NVIDIA 595.84

The `595.84` driver currently installed on the reference machine produces **seven
errors** against 7.4-rc1:

```
nvidia-drm/nvidia-drm-drv.c:67:10: fatal error: drm/drm_fb_helper.h: No such file or directory
nvidia-drm/nvidia-drm-crtc.c:2091:31: error: initialization of 'int (*)(struct drm_plane *, ...)' from incompatible pointer type 'void (*)(struct drm_plane *)'
nvidia-drm/nvidia-drm-crtc.c:2192:5: error: implicit declaration of function 'drm_atomic_helper_crtc_reset'
nvidia-drm/nvidia-drm-crtc.c:2301:6: error: 'struct drm_crtc_funcs' has no member named 'reset'
...
```

### Two independent problems

**1. The removed header.** `include/drm/drm_fb_helper.h` no longer exists.

**2. The `reset` callback removal.** 7.4 replaced the `reset` callback in
`struct drm_plane_funcs` and `struct drm_crtc_funcs` with the
`atomic_create_state` / `atomic_duplicate_state` pair, and dropped the
`drm_atomic_helper_plane_reset()` / `drm_atomic_helper_crtc_reset()` helpers.
The `595.84` driver still uses the old callbacks, so it cannot compile no matter
how the header issue is solved.

### Why 595.112.07 fixes problem 2 for free

`595.112.07` (2026-10-22) already implements the new atomic-state API. Building it
against 7.4-rc1 leaves **exactly one** error — the header include. The patch in
this repository resolves that last error, producing a clean build.

```
$ grep -cE 'error:' build.log
0
```

---

## Requirements

| Component | Version | Notes |
|---|---|---|
| Linux kernel source | `7.4.0-rc1` | `https://git.kernel.org/torvalds/t/linux-7.4-rc1.tar.gz` |
| Linux kernel build tree | `7.4.0-rc1` | Separate `O=` directory, prepared and built |
| NVIDIA driver source | `595.112.07` | `kernel-open/` from the `.run` installer |
| Compiler | GCC ≥ 12 | matching the kernel's `min-toolchain-version` |
| `modinfo` / `kmod` | any | used by the verification script |
| `patch` | any | GNU patch, or use `git apply` |

The NVIDIA open kernel modules are distributed under a **Dual MIT/GPL** license.
The proprietary driver package also contains a `kernel-open/` tree; both are
compatible with this patch.

---

## Quick start

### 1. Get the kernel source

```bash
curl -L -o linux-7.4-rc1.tar.gz \
    https://git.kernel.org/torvalds/t/linux-7.4-rc1.tar.gz
tar xzf linux-7.4-rc1.tar.gz
```

### 2. Prepare and build the kernel

```bash
make O=~/linux-7.4-rc1-build defconfig
# ... apply the configuration from config/ (see docs/KERNEL_CONFIGURATION.md)
make O=~/linux-7.4-rc1-build olddefconfig
make O=~/linux-7.4-rc1-build -j"$(nproc)"
```

### 3. Get the NVIDIA driver source

```bash
curl -L -o NVIDIA-595.112.07.run \
    https://us.download.nvidia.com/XFree86/Linux-x86_64/595.112.07/NVIDIA-Linux-x86_64-595.112.07.run
sh NVIDIA-595.112.07.run --extract-only --target ~/nvidia-595.112.07-extract
```

### 4. Apply the patch and build the modules

```bash
./scripts/build-nvidia-740.sh \
    --driver-src ~/nvidia-595.112.07-extract/kernel-open \
    --kernel-src ~/linux-7.4-rc1 \
    --kernel-out ~/linux-7.4-rc1-build \
    --jobs "$(nproc)"
```

The script applies the patch automatically (idempotently) and builds all five
modules.

### 5. Verify

```bash
./scripts/verify-build.sh \
    --kernel-out ~/linux-7.4-rc1-build \
    --driver-build ~/nvidia-595.112.07-extract/kernel-open-build
```

### 6. Install

```bash
sudo ./scripts/install-modules.sh \
    --kernel-src ~/linux-7.4-rc1 \
    --kernel-out ~/linux-7.4-rc1-build \
    --driver-build ~/nvidia-595.112.07-extract/kernel-open-build
```

Then reboot manually when ready.

---

## What the patch changes

**One file, one line.**

`nvidia-drm/nvidia-drm-drv.c` — the include is guarded by
`#if defined(NV_DRM_FBDEV_AVAILABLE)`, which the driver's own conftest logic
defines when the kernel provides a usable fbdev interface.

```
nvidia-drm/nvidia-drm-drv.c:67
```

Nothing else in the driver changes. The two call sites of
`drm_fb_helper_set_suspend_unlocked()` in `nv_drm_suspend_resume()` keep working
unchanged, because the function was preserved with an identical signature in
`include/drm/clients/drm_fbdev_helper.h`.

### Applying it manually

```bash
cd <driver-source>/kernel-open
patch -p1 < /path/to/nvidia-595.112.07-linux-7.4-drm-fbdev-helper.patch
```

or

```bash
git apply /path/to/nvidia-595.112.07-linux-7.4-drm-fbdev-helper.patch
```

### Applying it to a different driver version

The patch is intentionally minimal so it can be reused, but it was verified
against `595.112.07` only. For other versions, `scripts/apply-patch.sh` validates
that the expected line is present and exits with a clear error otherwise.

---

## Kernel configuration

The reference configuration targets an **inference-serving** workload on an
Intel Xeon E5-2680 v4 (Broadwell-EP, 14 cores / 28 threads, 2.4–3.3 GHz, 62 GiB
RAM) with an NVIDIA RTX 3060 Ti.

Full symbol-by-symbol breakdown: [`docs/KERNEL_CONFIGURATION.md`](docs/KERNEL_CONFIGURATION.md).

Highlights:

| Domain | Key symbols |
|---|---|
| Preemption | `PREEMPT`, `PREEMPT_DYNAMIC`, `SCHED_CORE`, `CPU_ISOLATION`, `NO_HZ_FULL`, `HZ_1000` |
| CPU | `X86_INTEL_PSTATE`, `X86_CPU_RESCTRL` (RDT/CAT), `CPU_FREQ_DEFAULT_GOV_PERFORMANCE` |
| Storage | `NVME_CORE`, `NVME_TCP`, `NVME_MULTIPATH`, `ZRAM`, `ZSWAP` |
| Networking | `WIREGUARD`, `BPF_SYSCALL`, `BPF_JIT`, `XDP_SOCKETS`, `NET_SCH_CAKE`, `NET_SCH_FQ` |
| Routing | `BRIDGE`, `BRIDGE_NETFILTER`, `BONDING`, `NET_TEAM`, `VXLAN`, `GENEVE`, `L2TP`, `MPLS`, `IP_VS`, `NET_VRF`, `MACSEC` |
| Virtualization | `KVM`, `VFIO`, `VFIO_IOMMU_TYPE1`, `IOMMUFD` |
| Security | `MODULE_SIG`, `MODULE_SIG_SHA512`, `SECURITY_LOCKDOWN_LSM`, `BPF_LSM`, `INTEGRITY` |

### Migration from 7.3.1

The configuration was carried over from the 7.3.1 tree and reconciled with
`make olddefconfig`. Of 5,116 shared symbols, only **76 config lines** differ.
Twenty-three symbols disappeared from the kernel in 7.4; three of them had been
enabled:

| Symbol | 7.3.1 | 7.4 status | Impact |
|---|---|---|---|
| `PER_VMA_LOCK` | `=y` | removed from the tree (only `PER_VMA_LOCK_STATS` remains) | per-VMA locking is lost |
| `DEBUG_WX` | `=y` | replaced by `CHECK_WX` (`=y`) | **stricter** — better memory protection |
| `PHYLINK` | `=m` | became an internal prompt-less symbol (`=y`) | **better** — no longer a module |

All remaining removed symbols were unset and had no effect.

---

## Framebuffer / console fallback stack

A requirement of this configuration is that the machine must **never boot into a
screen with no video output at all**, even if the NVIDIA driver fails to load.

Because Linux 7.4 refactored the fbdev subsystem, the legacy framebuffer path had
to be re-established explicitly. The configuration enables the full chain:

### Legacy framebuffer core

| Symbol | Purpose |
|---|---|
| `FB`, `FB_CORE` | framebuffer core |
| `FB_SYSMEM_FOPS`, `FB_SYSMEM_HELPERS` | framebuffer backed by system RAM |
| `FB_IOMEM_FOPS`, `FB_IOMEM_HELPERS` | framebuffer backed by MMIO |
| `FB_CFB_FILLRECT`, `FB_CFB_COPYAREA`, `FB_CFB_IMAGEBLIT` | accelerated blitting |

### Generic framebuffer drivers

| Symbol | Purpose |
|---|---|
| `FB_VESA` | VESA 2.0 fbdev — early-boot logo on legacy graphics |
| `FB_EFI` | EFI framebuffer — UEFI firmware-provided framebuffer |
| `SYSFB_SIMPLEFB` | generic simple-framebuffer from the firmware |
| `DRM_SIMPLEDRM` | DRM driver on top of a simple framebuffer |
| `DRM_BOCHS` | legacy framebuffer driver (Bochs / QEMU stdvga) |
| `DRM_QXL` | QXL framebuffer (QEMU with SPICE) |
| `DRM_VIRTIO_GPU` | virtio-gpu framebuffer (VM guests) |

### Console

| Symbol | Purpose |
|---|---|
| `VT`, `VT_CONSOLE` | virtual terminal / text console |
| `FRAMEBUFFER_CONSOLE` | console rendered into a framebuffer |
| `VGA_CONSOLE` | VGA text console |
| `DUMMY_CONSOLE` | minimal always-available emergency console |
| `EFI_STUB`, `EFI_EARLYCON` | UEFI stub and early console |
| `SERIAL_8250_CONSOLE` | serial console |

### New DRM client framework (7.4)

| Symbol | Purpose |
|---|---|
| `DRM_CLIENT_LIB` | DRM client library |
| `DRM_CLIENT_SELECTION` | client selection framework |
| `DRM_CLIENT_SETUP` | client setup support |
| `DRM_FBDEV_EMULATION` | legacy fbdev on top of a modesetting driver |

> **Mutual exclusion note.** `DRM_VESADRM` and `DRM_EFIDRM` declare
> `depends on (!SYSFB_SIMPLEFB || COMPILE_TEST)` — they are mutually exclusive
> with `SYSFB_SIMPLEFB`. Keeping `SYSFB_SIMPLEFB` enabled is the correct choice:
> it covers both the VESA and EFI cases without letting two drivers contend for
> the same device.

---

## Repository layout

```
.
├── README.md                                  This file
├── LICENSE                                    MIT (patch + tooling)
├── .gitignore
├── patches/
│   └── nvidia-595.112.07-linux-7.4-drm-fbdev-helper.patch
├── scripts/
│   ├── apply-patch.sh                         Apply the patch (idempotent)
│   ├── build-nvidia-740.sh                    Patch + build all modules
│   ├── verify-build.sh                        Validate modules and kernel config
│   └── install-modules.sh                     Privileged install (never reboots)
├── config/
│   └── linux-7.4.0-rc1.config                 Reference kernel configuration
└── docs/
    ├── KERNEL_CONFIGURATION.md                Symbol-by-symbol analysis
    ├── BUILD_REPORT.md                        Build log and measurements
    └── MIGRATION_7.3.1_TO_7.4.md              Configuration migration details
```

---

## Verification

`scripts/verify-build.sh` checks:

1. **Every NVIDIA module carries the expected `vermagic`.** A module built
   against a different kernel must never be installed — the 7.3.1 incident
   documented in `docs/BUILD_REPORT.md` was caused precisely by a stale module
   set in `/lib/modules`.
2. **All five required modules are present** — `nvidia.ko`, `nvidia-modeset.ko`,
   `nvidia-drm.ko`, `nvidia-uvm.ko` and `nvidia-peermem.ko`.
3. **The complete framebuffer / console stack is enabled** in the kernel config.

Expected output on a healthy tree:

```
--- NVIDIA modules ---
  [ OK ] nvidia-drm.ko (version 595.112.07) — vermagic '7.4.0-rc1 SMP preempt mod_unload'
  [ OK ] nvidia-modeset.ko (version 595.112.07) — vermagic '7.4.0-rc1 SMP preempt mod_unload'
  [ OK ] nvidia-peermem.ko (version 595.112.07) — vermagic '7.4.0-rc1 SMP preempt mod_unload'
  [ OK ] nvidia-uvm.ko (version 595.112.07) — vermagic '7.4.0-rc1 SMP preempt mod_unload'
  [ OK ] nvidia.ko (version 595.112.07) — vermagic '7.4.0-rc1 SMP preempt mod_unload'
  [ OK ] required module present: nvidia.ko
  ...
--- Kernel legacy framebuffer / console stack ---
  [ OK ] CONFIG_FB=y
  [ OK ] CONFIG_FB_CORE=y
  ...
 RESULT: all checks passed
```

---

## Installation

`scripts/install-modules.sh` performs the privileged steps in the correct order:

1. `make modules_install` — populate `/lib/modules/7.4.0-rc1`
2. Copy the NVIDIA `.ko` files into
   `/lib/modules/7.4.0-rc1/kernel/drivers/video/nvidia/`
3. `depmod 7.4.0-rc1`
4. `update-initramfs -u -k 7.4.0-rc1`
5. `make install` — install the kernel image into `/boot`
6. `update-grub`

> **Do not interrupt `update-initramfs`.** An interrupted run leaves a
> truncated initramfs that boots into a broken system. The script gives this
> step its own explicit stage for that reason.

> **The script never reboots.** Rebooting is always a deliberate manual step.

### DKMS alternative

To have DKMS manage the driver automatically, register the `595.112.07` tree
first and point DKMS at the patched source:

```bash
sudo cp -a ~/nvidia-595.112.07-extract/kernel-open /usr/src/nvidia-595.112.07
sudo cp ~/nvidia-595.112.07-extract/kernel-open/dkms.conf /usr/src/nvidia-595.112.07/
sudo dkms add -m nvidia -v 595.112.07
sudo dkms build -m nvidia -v 595.112.07 -k 7.4.0-rc1
sudo dkms install -m nvidia -v 595.112.07 -k 7.4.0-rc1
```

Note that the upstream `dkms.conf` shipped with the installer contains
placeholders (`__VERSION_STRING`, `__DKMS_MODULES`) that `nvidia-installer`
substitutes at install time. Those must be filled in when registering manually.

---

## Troubleshooting

### `fatal error: drm/drm_fb_helper.h: No such file or directory`

The patch was not applied. Run:

```bash
./scripts/apply-patch.sh <driver-source-dir>
```

and confirm the include now reads `<drm/clients/drm_fbdev_helper.h>`.

### `'struct drm_crtc_funcs' has no member named 'reset'`

The driver is too old for 7.4. `595.84` and earlier cannot work with the new
atomic-state API — upgrade to `595.112.07` or newer.

### Module loads but `vermagic` mismatch

A stale module set is installed. `modules_install` synchronizes the tree and
**removes** modules that no longer exist in the build, so NVIDIA modules can
disappear after a kernel rebuild. Re-run `scripts/install-modules.sh` to restore
them, then regenerate the initramfs.

### Black screen after boot

1. Confirm the NVIDIA modules are in the initramfs:
   `lsinitramfs /boot/initrd.img-7.4.0-rc1 | grep nvidia`
2. Boot with `nomodeset` to test the fallback stack:
   the `FB_VESA` / `FB_EFI` / `SYSFB_SIMPLEFB` drivers should still provide a
   console.
3. Check the kernel log for a DRM client setup failure:
   `dmesg | grep -iE 'drm|nvidia|fb'`

---

## References

- Linux 7.4-rc1 source — <https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tag/?h=v7.4-rc1>
- NVIDIA open GPU kernel modules — <https://github.com/NVIDIA/open-gpu-kernel-modules>
- NVIDIA 595.112.07 installer — <https://us.download.nvidia.com/XFree86/Linux-x86_64/595.112.07/NVIDIA-Linux-x86_64-595.112.07.run>
- DRM client framework documentation — <https://docs.kernel.org/gpu/drm-clients.html>
- DRM KMS helper documentation — <https://docs.kernel.org/gpu/drm-kms-helpers.html>

---

## License

The patch, scripts and documentation in this repository are released under the
**MIT License** — see [`LICENSE`](LICENSE).

The NVIDIA driver source itself is **not** included here and remains under
NVIDIA's **Dual MIT/GPL** license. The Linux kernel is licensed under the
**GPL-2.0**.
