# OpenWrt for the D-Link DSR-1000N (rev A1)

An unofficial OpenWrt **25.12.6** port for the D-Link DSR-1000N "Unified Services Router"
(Cavium Octeon Plus CN5010, BCM53115 switch, Atheros AR9160 Wi-Fi). D-Link's last firmware
for this model ships OpenSSL 0.9.8, TLS 1.0 only and a long list of unpatched CVEs; this
replaces it with a current Linux 6.12 kernel, nftables firewall, WPA3 and LuCI over TLS 1.3.

> **Status: running on real hardware since 2026-11-10.** Installed from flash, tested as
> described below. Not part of official OpenWrt. You need a serial console to install it.
> Flashing firmware can leave a device unbootable until recovered over the console; keep
> a backup of your flash (see [Install](#install)).

## What works

| | Status |
|---|---|
| Boot from flash | ✅ tested |
| sysupgrade (LuCI or `sysupgrade`), settings kept | ✅ tested (needs the fix below in the *running* image) |
| BCM53115 switch via DSA (`lan1`..`lan4`, `wan`), port isolation | ✅ tested |
| WAN1: DHCP, routing, firewall | ✅ tested |
| LAN, LuCI over HTTPS (TLS 1.3) | ✅ tested |
| Wi-Fi AR9160 (ath9k): client mode, used as WAN (WPA2, 5 GHz HT40, DHCP) | ✅ tested |
| Wi-Fi access point, WPA3, WPS push-button | ⚠️ supported, not yet tested |
| LuCI Save & Apply, settings kept across reboot | ✅ tested |
| WAN2/DMZ port (`wan2`, BCM5481 PHY) | ⚠️ driver binds, not yet tested with a cable |
| Real MAC addresses from D-Link product data | ✅ |
| Reset button (reboot / factory reset), WPS button | ✅ |
| LEDs: usb1, usb2, wps, 2.4g, 5g | ✅ |
| DS1337 battery-backed clock | ✅ |
| USB 2.0: storage (ext4, FAT, exFAT, NTFS), printer, phone tethering | ✅ drivers in image |
| CPU usage on the LuCI overview page | ✅ |
| Octeon crypto unit (new drivers): AES ECB/CBC/CTR, GHASH (so AES-GCM runs in hardware), optional 3DES; see [Crypto](#crypto) | ✅ tested (kernel self-tests incl. fuzzing, benchmark) |
| ChaCha20 assembly on the 64-bit Octeon (used by WireGuard): +40% over generic C | ✅ tested (kernel self-tests incl. fuzzing, benchmark) |

Included packages beyond OpenWrt's defaults: WireGuard, SQM (cake), ksmbd file sharing,
p910nd printer sharing, USB tethering (Android/iPhone), Wake-on-LAN, Dynamic DNS, full
`wpad-mbedtls` (WPS push-button). **Every** kernel module is built too
(`CONFIG_ALL_KMODS=y`): this is a custom kernel, so kernel modules from the official
OpenWrt package servers will not load; install them from your own build's
`bin/targets/octeon/generic/packages/` instead. Ordinary (non-kernel) packages from the
official servers work.

## Repository layout

| Path | What |
|---|---|
| `openwrt-v25.12.6-dlink-dsr-1000n.patch` | All changes as one patch against OpenWrt `v25.12.6` (commit in `OPENWRT_BASE`) |
| `openwrt/` | The same changes as files, in OpenWrt tree layout |
| `dsr1000n.diffconfig` | Build configuration |
| `build.sh` | Clone, patch, configure, build |
| `tools/` | Console and TFTP tools used to test and install (Windows PowerShell + Python) |
| `docs/hardware.md` | Board details: switch/port map, GPIOs, flash layout, U-Boot environment |

### The changes

| File | Purpose |
|---|---|
| `patches-6.12/160-pci-octeon-map-irq-not-init.patch` | **Linux bug fix:** `octeon_pci_pcibios_map_irq()` was `__init`, but PCI drivers loaded as modules (ath9k) call it after init memory is freed, causing an oops |
| `patches-6.12/161-staging-octeon-set-netdev-of_node.patch` | Octeon Ethernet attaches its DT node to the net_device, so DSA can find its conduit |
| `patches-6.12/162-dts-dlink-dsr-1000n-switch.patch` | BCM53115 (b53, MDIO address 30) with port labels; `wan2` label |
| `patches-6.12/163-staging-octeon-accept-length-errors.patch` | Don't drop frames for PIP length errors (Broadcom DSA tags trigger them) |
| `patches-6.12/164-dts-dlink-dsr-1000n-buttons.patch` | Reset and WPS buttons (gpio-keys-polled) |
| `patches-6.12/165-crypto-octeon-add-aes.patch` | **New drivers** for the Octeon crypto coprocessor (mainline only uses it for MD5/SHA): `octeon-aes` (AES-128/192/256 block cipher, ECB, CBC, CTR), `octeon-ghash` (GCM's GHASH on the Galois-field multiplier, so `gcm(aes)` runs entirely on the crypto unit) and `octeon-des3` (3DES ECB/CBC, not loaded by default). Each checks itself at load (FIPS-197 / SP 800-38A vectors, cross-checks against the generic code with random data and odd splits) and refuses to register on a mismatch. Used automatically by IPsec, SMB3 encryption, dm-crypt |
| `patches-6.12/176-crypto-mips-chacha-64bit.patch` | Linux's MIPS32r2 ChaCha assembly ported to the 64-bit n64 ABI and enabled for Octeon (register names, 5th argument in `a4`, 64-bit saves and pointer arithmetic). WireGuard uses it through the ChaCha library |
| `patches-6.12/166-staging-octeon-rx-fastpath.patch` | Octeon RX fast path (on by default via `octeon-accel`). Hands established flows straight from the driver's receive loop to the firewall's flowtable (needs software flow offloading on), skipping DSA's GRO pass, a second stack pass and the bridge. `echo 1 > /sys/module/octeon_ethernet/parameters/fastpath`; counters `fastpath_hits/misses/seen`. RAM-boot test: all transfers checksum-correct, ~+10% download / ~+40% upload through a test server on the router itself |
| `patches-6.12/167-staging-octeon-skb-reuse-switch.patch` | **Buffer reuse:** the PKO frees a transmitted buffer straight back into the hardware RX pool instead of an skb free + reallocation per packet. The driver's old code for this was compiled out with netfilter and its size check no longer matched current kernels; fixed, and the skb is reset to a freshly allocated state before reuse. Runtime switch `skb_reuse`, counter `skb_reused` |
| `patches-6.12/168-lib-string-aligned-word-memcmp.patch` | Generic `memcmp()` compares a word at a time when both buffers are aligned (MIPS otherwise gets a byte loop); the flowtable's key compare was ~6% of CPU |
| `patches-6.12/169-staging-octeon-cheaper-tx-bookkeeping.patch` | TX cleanup tasklet scheduled every 1024 packets as the code comment intends (the test was inverted), and no watchdog CSR write when the hardware frees the buffer |
| `patches-6.12/171-staging-octeon-add-octeon-fwd.patch` | RX hook + `cvm_oct_xmit_fpa_buffer()` in the driver, and the `octeon-fwd` module (see Performance) |
| `patches-6.12/172-netfilter-flowtable-export-inet-hook.patch` | Exports `nf_flow_offload_inet_hook` so octeon-fwd can find a port's flowtable |
| `patches-6.12/173-dts-dlink-dsr-1000n-wanlink.patch` | Switch port 5 (wired to `eth1`) as user port `wanlink`, fixed 1 Gb/s RGMII |
| `patches-6.12/174-net-dsa-b53-rgmii-on-531x5-port5.patch` | b53: BCM53115 port 5 in `enabled_ports` (it was left out, so the switch dropped frames to it) and RGMII advertised for it |
| `files/etc/uci-defaults/93-dsr1000n-wan-eth1` | Moves WAN to `eth1` via `br-wan` (wan + wanlink) on first boot, keeps WAN1's MAC; undo steps in the file |
| `package/kernel/linux/modules/netdevices.mk` | `kmod-octeon-fwd` package |
| `package/network/config/firewall4/patches/100-software-offload-on-lower-devices.patch` | fw4 registers the software flowtable on bridge members (`lan1`..`lan4`) instead of `br-lan`, so offloaded flows transmit directly to the port (no bridge, no neighbour lookup) |
| `files/etc/init.d/octeon-accel`, `files/etc/config/octeon_accel` | Applies `fastpath`, `skb_reuse`, `conduit_noqueue` (no qdisc on the Octeon ports) and `wqe_fwd` (octeon-fwd) at boot, all on; set an option to `0` and `/etc/init.d/octeon-accel reload` to turn it off. `des3` (hardware 3DES) is off; set it to `1` only for old VPN peers that need 3DES |
| `files/etc/uci-defaults/92-dsr1000n-octeon-accel` | Enables the above and software flow offloading on first boot |
| `files/etc/uci-defaults/91-dsr1000n-wifi-name` | The stock AR9160 card reports Atheros' reference ID 168c:2082, which OpenWrt's tables call "Ubiquiti SR71A" with a +7 dB TX power offset; corrects that entry to "Atheros AR9160", 0 dB, on this board |
| `package/kernel/linux/modules/crypto.mk` | `kmod-crypto-aes-octeon`, `kmod-crypto-ghash-octeon`, `kmod-crypto-des3-octeon` packages; `kmod-crypto-lib-chacha20` uses the ported ChaCha on Octeon |
| `image/Makefile` | `Device/dlink_dsr-1000n`: ELF kernel with appended DTB + squashfs, `sysupgrade.bin` |
| `config-6.12` | Kernel config, adds `MTD_SPLIT_ELF_FW` + firmware splitting, Broadcom PHY; removes drivers this board has no hardware for, and SMP (single core); `CVMSEG_SIZE=2`, no `LOCK_L2` (see Performance) |
| `base-files/lib/preinit/01_sysinfo` | Board detection from the DT model (U-Boot reports board type 20006, which OpenWrt calls ITUS_SHIELD) |
| `base-files/etc/board.d/01_network` | lan1-4 / wan, real MACs from product data |
| `base-files/lib/upgrade/platform.sh` | sysupgrade writes the `firmware` MTD partition |
| `files/etc/uci-defaults/90-dsr1000n-wan2-mac` | WAN2 MAC = base + 2 |
| `files/www/.../15_cpu.js` + rpcd ACL | CPU usage section on the LuCI overview page |

**Note:** `config-6.12` is shared by every Octeon device in OpenWrt. The trims here
(no SMP, no USB 3/SATA/MMC/SPI, etc.) suit the DSR-1000N only. Do not use this tree to
build images for other Octeon devices. Upstreaming would need a separate subtarget, or
only the patches (160 and 161 are generic fixes) and the DTS.

## Performance

Measured on hardware (single 500 MHz core), NAT between LAN hosts through the router
(hairpin: every packet takes Octeon RX → flowtable → Octeon TX), one direction at a time.
UDP rates are packets forwarded per second of offered load; full-size frames are offered at
gigabit line rate (~80.7 kpps).

| Configuration (cumulative) | 1472-byte UDP | 64-byte UDP |
|---|---|---|
| Software flow offloading only | — | ~33 kpps |
| + driver fast path (166), buffer reuse (167), `memcmp` (168), `CVMSEG_SIZE=2`, no `LOCK_L2` | ~66 kpps (~795 Mb/s) | ~67 kpps |
| + no qdisc on the DSA conduit `eth0` (was `fq_codel`) | ~77 kpps (~925 Mb/s) | — |
| + flowtable on the switch ports (fw4 patch) | 80.7 kpps, zero loss: line rate (~970 Mb/s) | ~115–120 kpps |
| + octeon-fwd (171/172): forwarding from the RX hardware buffer | 80.7 kpps, line rate | ~255–265 kpps |
| + octeon-fwd v5 (cached device lookups, one combined NAT checksum update, no per-packet divide), the default | **80.7 kpps, line rate** | **~317 kpps forwarded (load limit of the test PC), ~350 kpps estimated ceiling** |

TCP through NAT (multiple streams): **~917–954 Mb/s** per direction, at the ~941–954 Mb/s TCP
maximum on gigabit; single stream ~870 Mb/s; with data verification (64 MB each way)
~800–820 Mb/s. Latency added by the router: ~0.15 ms median idle.

### Second CPU link for WAN1

The board wires switch port 5 to the Octeon's second RGMII port (`eth1`); D-Link's firmware used
it as the WAN path. Patches 173/174 expose it as switch port `wanlink`, and
`uci-defaults/93-dsr1000n-wan-eth1` bridges `wan` + `wanlink` inside the switch (`br-wan`, no
IP) and moves the WAN interface to `eth1` (keeping WAN1's MAC). WAN1 traffic then has its own
1 Gb/s link into the CPU, untagged, instead of sharing `eth0` with the LAN.

Measured LAN PC ↔ router ↔ laptop on WAN1, 8 TCP streams each way (the laptop's single CPU core
limits the combined test):

| | Download only | Upload only | Both at once (total) |
|---|---|---|---|
| WAN1 sharing `eth0` with the LAN (before) | 943 Mb/s | 930 Mb/s | **942 Mb/s** (router CPU 99%) |
| WAN1 on its own link, `eth1` (default) | 952 Mb/s | 952 Mb/s | **1,434 Mb/s** (router CPU 75%) |

WAN2 (`eth2`) already has its own link; octeon-fwd covers it too.

### octeon-fwd

`kmod-octeon-fwd` hooks the octeon-ethernet RX loop before the network stack. For packets from
the Broadcom-tagged switch or a plain Octeon port (`eth1`, `wan2`) it looks the flow up in the
**kernel's own flowtable** (the one fw4 registers on the ports), applies the flowtable's
NAT/TTL/MAC rewrite in place, adds, keeps or removes the Broadcom tag for the output port (MAC from
the flow for bridge/DSA paths, from the confirmed neighbour entry for routed ones) and hands the
same FPA buffer to the PKO, which frees it back into the RX pool. No skb processing, network stack, DSA, bridge or qdisc per packet. Policy, flow setup,
timeouts and counters stay netfilter's; anything not matched (new connections, non-IPv4, IP
options, fragments, TCP FIN/RST, MTU, non-direct paths, Wi-Fi) takes the normal path unchanged.
Counters: `/sys/module/octeon_fwd/parameters/{hits,misses,passed}`; off switch `enable`, or
`option wqe_fwd '0'` in `/etc/config/octeon_accel`. Tested: checksum-verified TCP, unload and
reload under a 218 kpps flood, live on/off, no leaks.

Notes:
* Full-size forwarding is limited by the gigabit link, not the CPU; small packets are CPU bound
  (99% softirq).
* Latency under load in the hairpin test (~14 ms) sits on the test PC: shrinking the router's
  buffer pool to 256 did not change it.
* 168, `CVMSEG_SIZE=2` (async IOBDMA work requests) and no `LOCK_L2` (whole 128 KB L2 for packet
  data) only pay off once buffer reuse has removed the per-packet allocation cost.
* Tried and not kept: NAPI weight 64/128 (no gain / unstable), 2048–4096 packet buffers (no
  gain), conntrack accounting off (no gain), bypassing `__dev_queue_xmit()` for the DSA conduit
  (−7% on small packets), `receive_group_order=1` (−30% on small packets on one core).
* The WQE-level idea comes from D-Link's own firmware and from
  [octeon-flowtable](https://github.com/packerlschupfer/octeon-flowtable) (dual-core CN5020,
  separate flow engine); octeon-fwd is a separate implementation that reuses the kernel
  flowtable instead of keeping its own flow state.

### Crypto

The CN5010's crypto coprocessor has units for AES, 3DES, SHA-1/2, MD5 and a Galois-field
multiplier (GHASH). Mainline only used it for the hashes; patch 165 adds the rest. Kernel
`tcrypt`, one 500 MHz core, 1420–1424-byte blocks (1 MB/s ≈ 8 Mb/s, crypto only):

| Algorithm | Software | This image | Driver |
|---|---|---|---|
| AES-128 ECB | 16.0 MB/s | **131.7 MB/s** | `ecb-aes-octeon` |
| AES-128 CBC | — | **138.0 MB/s** | `cbc-aes-octeon` |
| AES-GCM (IPsec `rfc4106`, AES-128) | — | **53.5 MB/s** | `gcm_base(ctr-aes-octeon,ghash-octeon)` |
| GHASH | 32.1 MB/s | **161.7 MB/s** | `ghash-octeon` |
| SHA-1 | 18.1 MB/s | **168.5 MB/s** | `octeon-sha1` (mainline driver, now packaged) |
| 3DES ECB/CBC | 2.9 MB/s | **93.6 MB/s** | `octeon-des3`, only with `option des3 '1'` |
| ChaCha20 | 33.3 MB/s | **46.7 MB/s** | `chacha20-mips` (patch 176) |
| ChaCha20-Poly1305 (IPsec `rfc7539esp`) | 23.1 MB/s | **29.1 MB/s** | `chacha20-mips` + `poly1305-mips` |

ChaCha20 and Poly1305 have no hardware unit, and they cannot be translated onto the AES or
GHASH units (different operations), so they stay on the CPU; patch 176 makes them use the
existing MIPS assembly instead of C. For a VPN on this router, AES-GCM is the faster choice:
IPsec/IKEv2 with `aes128gcm16` or `aes256gcm16`. WireGuard always uses ChaCha20-Poly1305.

## Build

On Debian/Ubuntu with the [OpenWrt build dependencies](https://openwrt.org/docs/guide-developer/toolchain/install-buildsystem):

```bash
./build.sh
```

Output in `openwrt-build/bin/targets/octeon/generic/`: the `initramfs-kernel.bin` (RAM test
image) and `squashfs-sysupgrade.bin` (flash image).

## Install

You need the serial console: the front RJ45 "Console" port is RS-232 at 115200 8N1 with a
Cisco pinout. A Cisco console cable works, or a PC serial port with a cut Ethernet cable
(pin 3 = router TX to DB9 pin 2, pin 6 = router RX to DB9 pin 3, pin 4 = GND to DB9 pin 5).
Connect the PC's Ethernet to **LAN1**.

The `tools/` scripts automate every step below over `COM1` (edit the port name in the scripts
if needed); the commands are listed so you can also type them into any terminal.

1. **Stop U-Boot.** Power on and press a key at `Hit any key to stop autoboot`.
2. **TFTP server.** Give the PC `192.168.10.100/24` (no gateway), put the images in
   `tools/tftp/`, run `python tools/tftp_server.py 192.168.10.100`.
3. **Test from RAM first** (writes nothing; a power cycle returns to D-Link):
   ```
   setenv ipaddr 192.168.10.1
   setenv serverip 192.168.10.100
   tftpboot 0xaa00000 openwrt-dsr1000n-initramfs.elf
   bootoctlinux 0xaa00000 console=ttyS0,115200 mtdparts=phys_mapped_flash:640k(u-boot)ro,29696k(firmware)ro,2M(dlink-config)ro,-(dlink-data)ro
   ```
   (`tools/serial_ramboot.ps1` does this.)
4. **Back up the whole flash** from the RAM-booted OpenWrt: `cat /dev/mtd0 /dev/mtd1 ... > /tmp/full.bin`,
   then copy it to the PC (e.g. symlink into `/www` and download, or `scp`). Keep it.
5. **Flash** (`tools/serial_flash.ps1` does all of this and verifies CRC32 before erasing and after writing):
   ```
   setenv ipaddr 192.168.10.1
   setenv serverip 192.168.10.100
   tftpboot 0xaa00000 openwrt-dsr1000n-sysupgrade.bin
   crc32 0xaa00000 <size>                 (compare with the file's CRC32)
   setenv owrt_load cp.b 0xbdca0000 0xaa00000 0x1000000
   setenv owrt_boot bootoctlinux 0xaa00000 console=ttyS0,115200 mtdparts=phys_mapped_flash:640k(u-boot)ro,29696k(firmware),2M(dlink-config)ro,-(dlink-data)ro
   erase 0xbdca0000 0xbf99ffff
   cp.b 0xaa00000 0xbdca0000 <size>
   crc32 0xbdca0000 <size>                (must match again)
   setenv dlink_bootcmd bootFirmware
   setenv bootcmd run owrt_load owrt_boot
   saveenv
   reset
   ```
   **Do not power off during erase/write** (5–10 minutes on this flash).
6. First boot formats the overlay. LuCI is at `https://192.168.1.1`. **Set a root
   password** (System → Administration).

## Upgrade

Build a new `squashfs-sysupgrade.bin` and flash it from LuCI (System → Backup / Flash
Firmware). Settings are kept. No console needed.

## Recovery / going back to D-Link

Over the console, stop U-Boot, then either:

* **OpenWrt broken:** repeat step 5 with a known-good `sysupgrade.bin`, or boot the
  `initramfs` image from RAM (step 3) and run `sysupgrade` from there.
* **Back to D-Link, from your backup:** take bytes `0xA0000`..`0x1DA0000` (29 MB) of your full
  flash backup, TFTP them to `0xaa00000`, then
  `erase 0xbdca0000 0xbf99ffff`, `cp.b 0xaa00000 0xbdca0000 0x1d00000`,
  `setenv bootcmd bootFirmware`, `saveenv`, `reset`.
* **Back to D-Link, from a D-Link firmware file:** follow D-Link's own recovery guide
  (it loads the image to `0xaa00000` and runs `firm_flash`), then `setenv bootcmd bootFirmware`, `saveenv`.

## Known issues / to do

* **Upgrading from a build before commit "fix sysupgrade" fails safely** with
  `Could not open mtd device: image` (nothing is written; the router reboots unchanged).
  Older images looked for a partition called `image` instead of `firmware`. Fix the running
  system once, then upgrade as normal:
  ```
  sed -i 's/^\([[:space:]]*\)default_do_upgrade "\$tar_file"$/\1PART_NAME=firmware default_do_upgrade "$tar_file"/' /lib/upgrade/platform.sh
  ```

* WAN2 and Wi-Fi access-point mode not yet tested on hardware.
* **Save & Apply is slow, not broken.** With one 500 MHz core, a service takes 10–20 s to
  reload after Save & Apply, and Wi-Fi changes (radio restart, network reload, reconnect,
  DHCP) can take 30 s or more. Wait before checking whether a change took effect.
* Routing throughput is limited by the single 500 MHz core. Software flow offloading
  plus the driver fast path and buffer reuse (on by default, see [Performance](#performance))
  give the numbers below; turning any of them off costs speed, not function.
* The battery clock may hold D-Link's old time until NTP corrects it.

## Credits

* Device tree base (`dlink_dsr-1000n.dts`, `dlink_dsr-500n-1000n.dtsi`) by Aaro Koskinen, in mainline Linux.
* OpenWrt and the Linux kernel projects.

## License

GPL-2.0 (see `LICENSE`), the same as OpenWrt and the Linux kernel.
