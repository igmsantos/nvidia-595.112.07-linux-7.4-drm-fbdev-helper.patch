# Migration Guide — Linux 7.3.1 to 7.4.0-rc1

This document records exactly what changed when the reference configuration was
carried from the 7.3.1 kernel tree into the 7.4.0-rc1 tree, and why.

---

## 1. Procedure

```bash
# 1. Download and extract the 7.4.0-rc1 source
curl -L -o linux-7.4-rc1.tar.gz \
    https://git.kernel.org/torvalds/t/linux-7.4-rc1.tar.gz
tar xzf linux-7.4-rc1.tar.gz

# 2. Create a dedicated build directory
mkdir -p ~/linux-7.4-rc1-build

# 3. Carry the configuration over
cp ~/linux-7.3.1-build/.config ~/linux-7.4-rc1-build/.config

# 4. Reconcile with the new tree
make -C ~/linux-7.4-rc1 O=~/linux-7.4-rc1-build olddefconfig
```

`olddefconfig` resolves every dependency against the 7.4.0-rc1 Kconfig files and
writes the result to `.config`. **The generated `.config` is the only
authoritative record** — a symbol that was requested but dropped by
`olddefconfig` was never enabled.

---

## 2. Diff summary

| Metric | Value |
|---|---|
| Symbols present in both trees | 5,116 |
| Total differing config lines | 76 |
| Symbols removed by the kernel | 23 |
| Of those, previously enabled | 3 |

Most of the 76 differing lines are new compiler-option symbols introduced by
7.4 (`CC_OPT_*`), new driver options, and `ARCH_HAS_*` capability flags.

---

## 3. Removed symbols

### 3.1 Symbols that had been enabled

#### `PER_VMA_LOCK` — removed from the kernel

| | |
|---|---|
| 7.3.1 | `=y` |
| 7.4 | Symbol no longer exists |

The per-VMA locking feature was removed from the kernel entirely in 7.4. Only
the statistics counter survives:

```
mm/Kconfig.debug:272:config PER_VMA_LOCK_STATS
```

`PER_VMA_LOCK_STATS` merely exposes success/retry/failure counters for
page faults handled under per-VMA lock protection in `/proc/vmstat`. The
locking mechanism itself is gone — there is nothing to enable.

**Impact.** The system loses per-VMA locking. This affects the granularity of
fine-grained protection used by BPF-based LSMs and Landlock-style isolation
schemes. It does not affect the NVIDIA driver or any of the networking,
storage, or preemption features.

**Action.** None possible — the feature is not present in 7.4.

#### `DEBUG_WX` — superseded by `CHECK_WX`

| | |
|---|---|
| 7.3.1 | `=y` |
| 7.4 | `CHECK_WX` = `=y` (via `ARCH_HAS_CHECK_WX`) |

`DEBUG_WX` was removed and replaced by `CHECK_WX`, a stricter successor that
validates W^X at runtime rather than only at build time. The 7.4 configuration
gains the stronger check automatically.

**Impact.** **Improvement.** No action needed.

#### `PHYLINK` — became an internal symbol

| | |
|---|---|
| 7.3.1 | `=m` (loadable module) |
| 7.4 | `=y` (built-in, prompt-less) |

```kconfig
config PHYLINK
	tristate
	select PHYLIB
	select SWPHY
```

The `tristate` entry has no prompt, so it defaults to built-in. PHYlink is now
always available and cannot be unloaded.

**Impact.** **Improvement.** No action needed.

### 3.2 Symbols that were unset (no impact)

| Symbol | 7.3.1 | Note |
|---|---|---|
| `ANDROID_BINDER_IPC` | not set | Removed upstream. |
| `ARCH_HAS_DEBUG_WX` | `=y` | Capability flag, replaced by `ARCH_HAS_CHECK_WX`. |
| `ARCH_SUPPORTS_PER_VMA_LOCK` | `=y` | Capability flag for the removed feature. |
| `ARCH_WANT_HUGETLB_VMEMMAP_PREINIT` | `=y` | Capability flag. |
| `BFS_FS` | not set | Filesystem removed upstream. |
| `CRYPTO_XTS` | not set | Still exists in 7.4 (`crypto/Kconfig:729`); remains unset by choice. |
| `HAVE_PREEMPT_DYNAMIC` | `=y` | Capability flag, renamed internally. |
| `HAVE_PREEMPT_DYNAMIC_CALL` | `=y` | Capability flag. |
| `HID_KYSONA` | not set | HID driver removed upstream. |
| `LLC2` | not set | `llc2` filesystem removed upstream. |
| `MMU_GATHER_RCU_TABLE_FREE` | `=y` | Internal flag. |
| `MMU_GATHER_TABLE_FREE` | `=y` | Internal flag. |
| `MOXA_INTELLIO` | not set | Serial driver removed upstream. |
| `QCOM_PAS` | not set | Qualcomm PAS support removed. |
| `QCOM_SCM` | not set | Qualcomm SCM support removed. |
| `RUSTC_HAS_SPAN_FILE` | `=y` | Rust toolchain capability flag. |
| `SATA_INIC162X` | not set | SATA driver removed upstream. |
| `SPARSEMEM_VMEMMAP_PREINIT` | `=y` | Internal flag. |
| `TEST_BPF` | not set | BPF test-suite config removed upstream. |

### 3.3 Investigated and dismissed

`LANDLOCK` and `FS_VERITY` appeared to be missing from the migrated
configuration. Cross-checking the 7.3.1 reference tree showed that **neither was
ever enabled there** — they were unset in the original as well. This was a
false alarm caused by an incomplete grep, not a migration regression.

---

## 4. New symbols in 7.4

| Symbol | Value | Notes |
|---|---|---|
| `BPF_CRYPTO` | `=y` | BPF programs can call kernel crypto primitives. |
| `RCU_DEFER` | `=y` | Deferred RCU callback mechanism. |
| `VMEMMAP_OPTIMIZATION` | `=y` | Optimized sparse virtual memory map. |
| `PNFS_SCSI_LAYOUT` | `=y` | pNFS layout type for SCSI. |
| `CRYPTO_LIB_AES_XTS` | `=y` | AES-XTS cipher library. |
| `CHECK_WX` | `=y` | Strict W^X runtime validation. |
| `BPF_CRYPTO`, `SENSORS_*`, `TCP_CONG_ROCCET` | not set | New options, not required. |

Compiler-option symbols (`CC_OPT_*`) also appear in the diff — 7.4 adds a larger
set of compiler capability probes and warning flags. They are derived from the
toolchain and are not user-configurable.

---

## 5. Networking symbols renamed or removed

Several networking symbols from the 7.3.1 configuration do not exist in 7.4.
Each was verified against the 7.4.0-rc1 source tree:

| 7.3.1 symbol | 7.4 status | Resolution |
|---|---|---|
| `TCP_CONG_RENO` | Not a Kconfig symbol | Reno is built into the TCP core and is no longer separately selectable. `TCP_CONG_CUBIC` remains available. |
| `RFS_INDIRECT` | Renamed | Replaced by `RFS_ACCEL` (`=y`). |
| `RTO_FAST_OPEN` | Not present under that name | Fast open is handled by the core TCP implementation. |
| `TCP_AUTOTUNING` | Not present under that name | Buffer autotuning is unconditional in the core. |
| `SOFTNET` | Not present under that name | `SOFTNET` is an internal per-CPU structure, not a configurable symbol. |
| `BPF_STREAM_PARSER` | Exists | Was unset in 7.3.1 as well; remains unset. Requires `CGROUP_BPF`. |

None of these represent a functional regression — in every case the capability
is either built into the core or covered by a renamed symbol.

---

## 6. Netfilter dependency chain

The legacy `iptables` symbols in the 7.4 configuration are only reachable
through a dependency chain that must be satisfied in order:

```
NETFILTER_ADVANCED=y          → unlocks BRIDGE_NETFILTER, IP6_NF_NAT
NETFILTER_XTABLES_LEGACY=y    → unlocks the legacy iptables compatibility layer
IP_NF_IPTABLES_LEGACY=m       → unlocks IP_NF_FILTER / IP_NF_NAT / IP_NF_MANGLE
IP6_NF_IPTABLES_LEGACY=m      → unlocks the IPv6 equivalents
```

`IP_NF_TARGET_MASQUERADE` and `IP6_NF_TARGET_MASQUERADE` select
`NETFILTER_XT_TARGET_MASQUERADE` and, in the IPv6 case, additionally depend on
`IP6_NF_NAT`.

This chain was applied in dependency order and every resulting symbol was
re-verified in the final `.config` after `olddefconfig`.

---

## 7. MPLS dependency chain

`MPLS` is a `bool` (not a tristate) at `net/mpls/Kconfig:6`:

```kconfig
menuconfig MPLS
	bool "MultiProtocol Label Switching"
	default n
```

Its sub-options are tristate:

| Symbol | Depends on | Enabled value |
|---|---|---|
| `NET_MPLS_GSO` | — | `=m` |
| `MPLS_ROUTING` | `NET_IP_TUNNEL \|\| NET_IP_TUNNEL=n`, `SYSCTL` | `=m` |
| `MPLS_IPTUNNEL` | `LWTUNNEL`, `MPLS_ROUTING` | `=m` |

`LWTUNNEL` was enabled first so that `MPLS_IPTUNNEL` could be satisfied.

---

## 8. Validation checklist

After any configuration change in this project:

1. Run `make -C ~/linux-7.4-rc1 O=~/linux-7.4-rc1-build olddefconfig`.
2. Inspect the resulting `.config` directly — do not rely on the fact that
   `scripts/config --enable` reported success.
3. Confirm every symbol that matters for the target workload is present with the
   expected value.
4. Rebuild the kernel.
5. Rebuild the NVIDIA modules against the new build tree.
6. Run `scripts/verify-build.sh` to check vermagic and the framebuffer stack.
7. Re-install modules and regenerate the initramfs.

**Never interrupt `update-initramfs`.** A truncated initramfs boots into a
broken system — this was observed during the 7.3.1 work.

---

## 9. Version history

| Kernel | Driver | Status |
|---|---|---|
| 7.3.1 | NVIDIA 595.84 | Working. Five modules built and installed. |
| 7.4.0-rc1 | NVIDIA 595.84 | **Does not build** — the DRM atomic-state rework removed the `reset` callback the driver relies on. |
| 7.4.0-rc1 | NVIDIA 595.112.07 | **Working** — one-line include patch required, documented in this repository. |
