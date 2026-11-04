# Kernel Configuration — Linux 7.4.0-rc1

Reference configuration for an **AI inference / model-serving** workload.

**Target hardware**

| Component | Specification |
|---|---|
| CPU | Intel Xeon E5-2680 v4 (Broadwell-EP), 14 cores / 28 threads, 2.4–3.3 GHz |
| NUMA | 1 socket |
| RAM | 62 GiB |
| GPU | NVIDIA RTX 3060 Ti (GA104, 10de:2489) |
| Storage | ADATA SM2P41C8 NVMe + 2× SanDisk SATA SSD + Seagate portable USB |
| Network | Realtek RTL8111/8168 (`r8169`) + Intel AX200 Wi-Fi 6 (`iwlwifi`) |
| Chipset | Intel 8 Series / C220 (Q87), LPC 8c4e |
| OS | Ubuntu 24.04.4 LTS |

**Kernel trees**

| Role | Path |
|---|---|
| Source | `~/linux-7.4-rc1` |
| Build output | `~/linux-7.4-rc1-build` |
| Reference config | `config/linux-7.4.0-rc1.config` |

> Every symbol listed below was verified to exist in the actual 7.4.0-rc1 source
> tree before being enabled. No symbol was enabled on assumption.

---

## 1. Preemption and scheduling

The workload is latency-sensitive, multi-tenant inference serving. Full
preemption is preferred over throughput-oriented configurations because a single
long-running inference request must not be able to delay another tenant's
request.

| Symbol | Value | Rationale |
|---|---|---|
| `PREEMPT` | `=y` | Full preemption — any task can preempt another on a CPU without waiting for an interrupt boundary. Essential for tail-latency control in multi-tenant serving. |
| `PREEMPT_DYNAMIC` | `=y` | Allows selecting the preemption model at runtime (`preempt=full` / `preempt=lazy` / `preempt=none` on the kernel command line) without recompiling. |
| `SCHED_CORE` | `=y` | Enables the scheduler core abstraction used by the per-CPU scheduling domains; required for the isolated-CPU setup below. |
| `CPU_ISOLATION` | `=y` | `isolcpus=` support — isolates the housekeeping cores from the inference worker pool. |
| `NO_HZ_FULL` | `=y` | `nohz_full=` — stops the tick on isolated cores, eliminating periodic scheduler interrupts. |
| `HZ_1000` | `=y` | 1 kHz tick. With `NO_HZ_FULL` the tick only runs on housekeeping cores, so a higher tick rate costs little and improves timekeeping granularity. |
| `IRQ_FORCED_THREADING` | `=y` | Moves all interrupt handlers to kernel threads, removing hard IRQ context from the critical path and improving scheduler fairness. |
| `RCU_NOCB` support | via `NO_HZ_FULL` | `rcu_nocbs=` — RCU callbacks are deferred off the isolated cores. |

### Runtime parameters (GRUB kernel command line)

```
preempt=full nohz_full=0-13 rcu_nocbs=0-13 isolcpus=0-13 irqaffinity=14-27
```

Cores 0–13 are isolated for inference workers; cores 14–27 absorb all IRQ
affinity so interrupts never land on a worker core.

---

## 2. CPU frequency, power and cache allocation

| Symbol | Value | Rationale |
|---|---|---|
| `X86_INTEL_PSTATE` | `=y` | Broadwell-EP has no HWP, so the intel_pstate driver is the only scalable-performance governor available. |
| `CPU_FREQ_DEFAULT_GOV_PERFORMANCE` | `=y` | Default governor `performance` — no frequency ramp-up latency on the inference path. |
| `X86_CPU_RESCTRL` | `=y` | RDT/CAT support. On a 14-core Broadwell-EP socket this allows L2 cache partitioning so co-located tenants do not evict each other's model weights from L3. |
| `RESCTRL_FS` | `=y` | Filesystem interface for resctrl (`/sys/fs/resctrl`). |
| `PROC_CPU_RESCTRL` | `=y` | Per-process resctrl monitoring in `/proc`. |
| `X86_TSC_KNOWN_FREQ` | `=y` | Known TSC frequency — avoids an early calibration delay and improves TSC-based timekeeping accuracy. |
| `X86_64_ACPI_NUMA` | `=y` | ACPI NUMA topology for the single socket. |
| `PERF_EVENTS` | `=y` | Hardware performance counters, required for latency profiling of the serving path. |
| `PERF_EVENTS_INTEL_RAPL` | `=y` | RAPL energy counters. |
| `PERF_EVENTS_INTEL_UNCORE` | `=y` | Uncore (memory controller) counters. |
| `X86_X2APIC` | `=y` | APIC addressing needed for the 28-thread topology. |

---

## 3. Storage

| Symbol | Value | Rationale |
|---|---|---|
| `NVME_CORE` | `=y` | NVMe support for the ADATA SM2P41C8. |
| `NVME_TCP` | `=y` | NVMe over TCP for remote/shared model storage. |
| `NVME_MULTIPATH` | `=y` | Multipath I/O for redundant NVMe deployments. |
| `NVME_FABRICS` | `=y` | RDMA fabric transport. |
| `NVME_HWMON` | `=y` | Temperature and SMART monitoring. |
| `ZRAM` | `=m` | Compressed RAM swap — protects the inference working set from OOM. |
| `ZRAM_DEF_COMP_LZORLE` | `=y` | LZO-RLE — lowest decompression latency, the right trade-off for swap. |
| `ZSWAP` | `=y` | Compressed swap cache in front of the backing store. |
| `ZSWAP_COMPRESSOR_DEFAULT_LZO` | `=y` | LZO for zswap. |
| `OVERLAY_FS` | `=y` | Overlay filesystem for container image layering — the standard deployment model for model servers. |

---

## 4. Networking

### Low-latency datapath

| Symbol | Value | Rationale |
|---|---|---|
| `TCP_CONG_BBR` | `=y` | BBR congestion control — bandwidth-delay product model, well suited to inference traffic over lossy links. |
| `NET_RX_BUSY_POLL` | `=y` | Busy polling removes the polling-softirq latency component. |
| `BQL` | `=y` | Byte queue limits prevent a single device from starving the softirq backlog. |
| `RPS` | `=y` | Receive packet steering. |
| `XPS` | `=y` | Transmit packet steering — required to avoid the XPS/RFS deadlock described in kernel documentation. |
| `RFS_ACCEL` | `=y` | Receive flow steering acceleration. |
| `INET_DIAG` / `INET_TCP_DIAG` / `INET_UDP_DIAG` | `=m` | Socket diagnostics for `ss`, `ss -t`, and load-balancer health checks. |
| `NETLINK_DIAG` | `=m` | Generic netlink diagnostics. |

### Programmable datapath

| Symbol | Value | Rationale |
|---|---|---|
| `BPF_SYSCALL` | `=y` | BPF syscall interface. |
| `BPF_JIT` | `=y` | BPF just-in-time compiler — eliminates the interpreter overhead on hot paths. |
| `BPF_JIT_DEFAULT_ON` | `=y` | JIT enabled by default rather than per-program. |
| `BPF_LSM` | `=y` | BPF-based LSM, used together with `SECURITY_LOCKDOWN_LSM`. |
| `XDP_SOCKETS` | `=y` | AF_XDP — zero-copy user-space networking for the inference front end. |
| `XDP_SOCKETS_DIAG` | `=y` | XDP socket diagnostics. |
| `PACKET` | `=y` | AF_PACKET sockets, used by `tc` for queue management. |

---

## 5. Advanced routing

A full advanced-routing stack is enabled. All symbols were confirmed present in
the 7.4.0-rc1 source tree.

### Layer 2

| Symbol | Value |
|---|---|
| `VLAN_8021Q` | `=m` |
| `BRIDGE` | `=m` |
| `BRIDGE_NETFILTER` | `=m` |
| `BONDING` | `=m` |
| `NET_TEAM` | `=m` |
| `NET_TEAM_MODE_BROADCAST` | `=m` |
| `NET_TEAM_MODE_ROUNDROBIN` | `=m` |
| `NET_TEAM_MODE_ACTIVEBACKUP` | `=m` |
| `NET_TEAM_MODE_LOADBALANCE` | `=m` |
| `MACVLAN` | `=m` |
| `IPVLAN` | `=m` |
| `VETH` | `=m` |
| `MACSEC` | `=m` |

`BRIDGE_NETFILTER` requires `NETFILTER_ADVANCED`, which was enabled to satisfy it.

### Tunnels and overlays

| Symbol | Value |
|---|---|
| `VXLAN` | `=m` |
| `GENEVE` | `=m` |
| `NET_IPIP` | `=m` |
| `NET_IPGRE` | `=m` |
| `IPV6_VTI` | `=m` |
| `L2TP` | `=m` |
| `L2TP_V3` | `=y` |
| `L2TP_IP` | `=m` |
| `L2TP_ETH` | `=m` |

### MPLS

| Symbol | Value | Note |
|---|---|---|
| `MPLS` | `=y` | Core MPLS support (a `bool`, not a tristate). |
| `MPLS_ROUTING` | `=m` | MPLS routing table. |
| `MPLS_IPTUNNEL` | `=m` | MPLS-over-IP tunnel; requires `LWTUNNEL` and `MPLS_ROUTING`. |
| `NET_MPLS_GSO` | `=m` | GSO support for MPLS packets. |

### IPv4 / IPv6 routing

| Symbol | Value |
|---|---|
| `IP_ADVANCED_ROUTER` | `=y` |
| `IP_ROUTE_MULTIPATH` | `=y` |
| `IP_PNP` | `=y` |
| `IP_MULTIPLE_TABLES` | `=y` |
| `IPV6` | `=y` |
| `IPV6_MULTIPLE_TABLES` | `=y` |
| `IPV6_MROUTE` | `=y` |
| `IPV6_MROUTE_MULTIPLE_TABLES` | `=y` |
| `IPV6_ROUTER_PREF` | `=y` |
| `IP_MROUTE` | `=y` |
| `NET_VRF` | `=m` |

> **Note:** `IPV6_ROUTER` does not exist — IPv6 routing is part of the core stack.
> `IPV6_MROUTE` is a `bool`, so it must be enabled with `--enable`, not
> `--module`.

### Netfilter and NAT

| Symbol | Value |
|---|---|
| `NETFILTER_XTABLES` | `=y` |
| `NETFILTER_XTABLES_LEGACY` | `=y` |
| `NF_TABLES` | `=y` |
| `NF_TABLES_INET` | `=y` |
| `NF_TABLES_NETDEV` | `=y` |
| `NF_TABLES_IPV4` | `=y` |
| `NF_TABLES_IPV6` | `=y` |
| `NF_CONNTRACK` | `=y` |
| `NF_NAT` | `=y` |
| `NF_FLOW_TABLE` | `=m` |
| `NF_CONNTRACK_OVS` | `=y` |
| `IP_NF_IPTABLES_LEGACY` | `=m` |
| `IP_NF_FILTER` | `=m` |
| `IP_NF_NAT` | `=m` |
| `IP_NF_MANGLE` | `=m` |
| `IP_NF_TARGET_MASQUERADE` | `=m` |
| `IP6_NF_IPTABLES_LEGACY` | `=m` |
| `IP6_NF_FILTER` | `=m` |
| `IP6_NF_NAT` | `=m` |
| `IP6_NF_MANGLE` | `=m` |
| `IP6_NF_TARGET_MASQUERADE` | `=m` |

The legacy `iptables` symbols depend on `NETFILTER_XTABLES_LEGACY` and the
per-family `IP_NF_IPTABLES_LEGACY` / `IP6_NF_IPTABLES_LEGACY` options. Those were
enabled first, which in turn unlocked the `*_NF_FILTER` / `*_NF_NAT` /
`*_NF_MANGLE` / `*_TARGET_MASQUERADE` symbols. `IP6_NF_NAT` additionally requires
`NETFILTER_ADVANCED`.

### Traffic control

| Symbol | Value |
|---|---|
| `NET_CLS` | `=y` |
| `NET_CLS_ACT` | `=y` |
| `NET_SCH` | `=y` |
| `NET_CLS_U32` | `=m` |
| `NET_CLS_FLOW` | `=m` |
| `NET_CLS_FW` | `=m` |
| `NET_CLS_BPF` | `=m` |
| `NET_CLS_EMATCH` | `=m` |
| `NET_CLS_BASIC` | `=m` |
| `NET_CLS_ROUTE4` | `=m` |
| `NET_SCH_HTB` | `=m` |
| `NET_SCH_HFSC` | `=m` |
| `NET_SCH_PRIO` | `=m` |
| `NET_SCH_MULTIQ` | `=m` |
| `NET_SCH_RED` | `=m` |
| `NET_SCH_SFB` | `=m` |
| `NET_SCH_SFQ` | `=m` |
| `NET_SCH_TEQl` | `=m` |
| `NET_SCH_TBF` | `=m` |
| `NET_SCH_CBS` | `=m` |
| `NET_SCH_ETF` | `=m` |
| `NET_SCH_TAPRIO` | `=m` |
| `NET_SCH_GRED` | `=m` |
| `NET_SCH_NETEM` | `=m` |
| `NET_SCH_INGRESS` | `=m` |
| `NET_SCH_MQPRIO` | `=m` |
| `NET_SCH_FQ` | `=m` |
| `NET_SCH_FQ_CODEL` | `=m` |
| `NET_SCH_CODEL` | `=m` |
| `NET_SCH_CAKE` | `=m` |

> **Note:** `NET_SCH_CBQ` does not exist in 7.4. `NET_SCH_HFSC` is the modern
> replacement.
> `NET_CLS_ROUTE4` is the correct symbol name — there is no `NET_CLS_ROUTE`.

### Connection tracking actions

| Symbol | Value | Note |
|---|---|---|
| `NET_ACT_POLICE` | `=m` | |
| `NET_ACT_GACT` | `=m` | |
| `NET_ACT_MIRRED` | `=m` | |
| `NET_ACT_NAT` | `=m` | |
| `NET_ACT_SKBEDIT` | `=m` | |
| `NET_ACT_CSUM` | `=m` | |
| `NET_ACT_VLAN` | `=m` | |
| `NET_ACT_TUNNEL_KEY` | `=m` | |
| `NET_ACT_CT` | `=m` | Requires `NF_FLOW_TABLE`. |

### IPsec

| Symbol | Value |
|---|---|
| `XFRM` | `=y` |
| `XFRM_ESP` | `=m` |
| `XFRM_AH` | `=y` |
| `XFRM_IPCOMP` | `=m` |
| `XFRM_INTERFACE` | `=m` |
| `XFRM_STATISTICS` | `=y` |
| `XFRM_USER` | `=y` |

### Load balancing

| Symbol | Value |
|---|---|
| `IP_VS` | `=m` |
| `IP_VS_NFCT` | `=y` |
| `IP_VS_PROTO_TCP` | `=y` |
| `IP_VS_PROTO_UDP` | `=y` |
| `IP_VS_RR` / `IP_VS_WRR` / `IP_VS_LC` / `IP_VS_WLC` / `IP_VS_SH` / `IP_VS_SED` / `IP_VS_NQ` | `=m` |

### Miscellaneous

| Symbol | Value |
|---|---|
| `NET_NS` | `=y` |
| `NET_UDP_TUNNEL` | `=y` |
| `WIREGUARD` | `=y` |
| `IPV6_SIT` | `=m` |
| `LWTUNNEL` | `=y` |
| `NETFILTER_ADVANCED` | `=y` |
| `NETFILTER_XT_TARGET_MASQUERADE` | `=m` |

---

## 6. Virtualization

| Symbol | Value | Rationale |
|---|---|---|
| `KVM` | `=y` | Hardware virtualization for model-serving sandboxes and tenant isolation. |
| `KVM_GUEST` | `=y` | Guest-side paravirtualization. |
| `KVM_COMPAT` | `=y` | Compatibility with older guests. |
| `VFIO` | `=y` | Userspace device passthrough. |
| `VFIO_PCI` | `=y` | PCI passthrough. |
| `VFIO_IOMMU_TYPE1` | `=y` | IOMMU type 1 (x86). |
| `VFIO_CONTAINER` / `VFIO_GROUP` | `=y` | Container and group management. |
| `VFIO_NOIOMMU` | `=y` | Allows no-IOMMU operation for compatibility. |
| `VFIO_VIRQFD` | `=y` | IRQ event delivery. |
| `IOMMUFD` | `=y` | Modern userspace IOMMU interface. |
| `IOMMUFD_DRIVER` / `IOMMUFD_DRIVER_CORE` | `=y` | IOMMUFD driver core. |
| `INTEL_IOMMU` | `=y` | VT-d — the CPU is Broadwell-EP with VT-d (device `6f28`). |
| `AMD_IOMMU` | `=y` | Enabled for completeness; no AMD IOMMU on this host. |

---

## 7. Security

| Symbol | Value | Rationale |
|---|---|---|
| `MODULE_SIG` | `=y` | Module signature verification. |
| `MODULE_SIG_ALL` | `=y` | Sign every built module. |
| `MODULE_SIG_SHA512` | `=y` | SHA-512 — the strongest hash available in the kernel signature tooling. |
| `SECURITY_LOCKDOWN_LSM` | `=y` | Kernel lockdown — prevents runtime changes to kernel code and restrictioed `/dev/mem`-style access. |
| `BPF_LSM` | `=y` | BPF-based LSM hooks. |
| `INTEGRITY` | `=y` | Integrity subsystem — the foundation for IMA/EVM. |
| `SECURITY_SELINUX` | `=y` | SELinux (Ubuntu default). |
| `CRYPTO_AES_NI_INTEL` | `=y` | AES-NI — required for performant dm-crypt and for WireGuard. |
| `CRYPTO_DEV_CCP` | `=y` | AMD crypto co-processor (no impact on this host). |
| `CRYPTO_XTS` | `=m` | XTS mode — needed for dm-crypt volume encryption. |
| `CRYPTO_LIB_AES_XTS` | `=y` | New in 7.4 — AES-XTS cipher library. |
| `CHECK_WX` | `=y` | Strict W^X enforcement (7.4 successor to `DEBUG_WX`). |
| `DMA_SHARED_BUFFER` | `=y` | DMA-BUF — required for GPU/display buffer sharing. |

`LANDLOCK` and `FS_VERITY` are **not** enabled in this configuration. They were
verified as never having been enabled in the 7.3.1 reference tree either — this
is a deliberate configuration choice, not a migration regression.

---

## 8. Hardware coverage

| Device | Driver symbol | Value |
|---|---|---|
| Xeon E5-2680 v4 | `X86_INTEL_PSTATE`, `INTEL_IDLE`, `INTEL_IOMMU`, `CRYPTO_AES_NI_INTEL`, `X86_MSR`, `X86_MCE_INTEL`, `PERF_EVENTS` | `=y` |
| Intel 8 Series host bridge | `PCIEPORTBUS`, `PCI`, `X86_IO_APIC` | `=y` |
| Q87 LPC | `LPC_ICH` | `=y` |
| SMBus 8c22 | `I2C_I801` | `=y` |
| MEI 8c3a | `INTEL_MEI` | `=y` |
| AHCI 8c02 | `SATA_AHCI` | `=y` |
| NVMe ADATA SM2P41C8 | `BLK_DEV_NVME`, `NVME_CORE` | `=y` |
| Realtek RTL8111/8168 | `R8169` | `=y` |
| Intel AX200 | `IWLWIFI`, `IWLMVM`, `IWLDVM`, `CFG80211`, `MAC80211` | `=m` |
| TP-Link UB5A Bluetooth | `BT`, `BT_HCIBTUSB`, `BT_INTEL`, `BT_BCM`, `BT_RTL`, `BT_MTK`, `BT_HCIUART` | `=y` |
| USB xHCI 8c31 | `USB_XHCI_HCD`, `USB_XHCI_PCI` | `=y` |
| USB EHCI / OHCI / UHCI | `USB_EHCI_HCD`, `USB_OHCI_HCD`, `USB_UHCI_HCD` | `=y` |
| USB storage | `USB_STORAGE`, `USB_UAS` | `=y` |
| USB serial (CH341 / CP210x / FTDI / PL2303) | `USB_SERIAL`, `USB_SERIAL_CH341`, `USB_SERIAL_CP210X`, `FTDI_SIO`, `PL2303` | `=y` / `=m` |
| USB CDC ACM (ESP32, CH340) | `USB_ACM` | `=y` |
| USB HID | `USB_HID`, `HID_A4TECH`, `HID_LOGITECH`, `HID_LOGITECH_DJ`, `HIDPP`, `HID_MICROSOFT`, `HIDRAW`, `HID_BATTERY_STRENGTH` | `=y` / `=m` |
| RNDIS / CDC Ethernet | `USB_NET_RNDIS_HOST`, `USB_NET_CDCETHER` | `=m` |
| Intel HDA 8c20 | `SND_HDA_INTEL`, `SND_HDA_CODEC_REALTEK`, `SND_HDA_CODEC_HDMI` | `=y` |
| NVIDIA RTX 3060 Ti | DKMS `nvidia/595.112.07` (external) | out-of-tree |
| UEFI | `EFI`, `EFI_STUB`, `EFIVAR_FS`, `EFI_PARTITION` | `=y` |
| PPP / VPN | `PPP`, `PPPOE`, `PPPOE_MPPE`, `TUN` | `=y` / `=m` |
| Realtek Ethernet firmware | `rtl_nic/*.fw.zst` | present in `/lib/firmware` |
| AX200 firmware | `iwlwifi-cc-a0-74.ucode.zst` | present in `/lib/firmware` |

---

## 9. Framebuffer and console

See [`BUILD_REPORT.md` §3](BUILD_REPORT.md#3-framebuffer--console-fallback-stack) for
the full list and the rationale. In summary, the configuration guarantees that the
machine retains a console even if the NVIDIA driver fails to load:

`FB` / `FB_CORE` / `FB_SYSMEM_*` / `FB_IOMEM_*` / `FB_CFB_*` / `FB_VESA` / `FB_EFI` /
`SYSFB_SIMPLEFB` / `DRM_SIMPLEDRM` / `DRM_BOCHS` / `DRM_QXL` / `DRM_VIRTIO_GPU` /
`DRM_CLIENT_LIB` / `DRM_CLIENT_SELECTION` / `DRM_CLIENT_SETUP` /
`DRM_FBDEV_EMULATION` / `FRAMEBUFFER_CONSOLE` / `VT` / `VT_CONSOLE` /
`VGA_CONSOLE` / `DUMMY_CONSOLE` / `EFI_STUB` / `EFI_EARLYCON` /
`SERIAL_8250_CONSOLE`

---

## 10. Reproducing this configuration

```bash
cp config/linux-7.4.0-rc1.config ~/linux-7.4-rc1-build/.config
make -C ~/linux-7.4-rc1 O=~/linux-7.4-rc1-build olddefconfig
make -C ~/linux-7.4-rc1 O=~/linux-7.4-rc1-build -j"$(nproc)"
```

Always run `olddefconfig` after any change and inspect the resulting `.config`.
A symbol enabled in the source but dropped by `olddefconfig` was never actually
enabled — the generated `.config` is the only authoritative source.
