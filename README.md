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
| Boot from flash, sysupgrade from LuCI (settings kept) | ✅ |
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
| AES in the Octeon crypto unit (`octeon-aes`, new driver): ~150 MB/s vs 14 MB/s in software | ✅ tested (test vectors, benchmark) |

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
| `patches-6.12/165-crypto-octeon-add-aes.patch` | **New driver:** AES-128/192/256 (block cipher, ECB, CBC) on the Octeon crypto coprocessor. Mainline only uses it for MD5/SHA. Checks FIPS-197 / SP 800-38A test vectors at load and refuses to register if they fail. Used automatically by IPsec, SMB3 encryption, dm-crypt; `modprobe octeon-aes bench=1` prints a benchmark |
| `package/kernel/linux/modules/crypto.mk` | `kmod-crypto-aes-octeon` package |
| `image/Makefile` | `Device/dlink_dsr-1000n`: ELF kernel with appended DTB + squashfs, `sysupgrade.bin` |
| `config-6.12` | Kernel config, adds `MTD_SPLIT_ELF_FW` + firmware splitting, Broadcom PHY; removes drivers this board has no hardware for, and SMP (single core) |
| `base-files/lib/preinit/01_sysinfo` | Board detection from the DT model (U-Boot reports board type 20006, which OpenWrt calls ITUS_SHIELD) |
| `base-files/etc/board.d/01_network` | lan1-4 / wan, real MACs from product data |
| `base-files/lib/upgrade/platform.sh` | sysupgrade writes the `firmware` MTD partition |
| `files/etc/uci-defaults/90-dsr1000n-wan2-mac` | WAN2 MAC = base + 2 |
| `files/www/.../15_cpu.js` + rpcd ACL | CPU usage section on the LuCI overview page |

**Note:** `config-6.12` is shared by every Octeon device in OpenWrt. The trims here
(no SMP, no USB 3/SATA/MMC/SPI, etc.) suit the DSR-1000N only. Do not use this tree to
build images for other Octeon devices. Upstreaming would need a separate subtarget, or
only the patches (160 and 161 are generic fixes) and the DTS.

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

* WAN2 and Wi-Fi access-point mode not yet tested on hardware.
* **Save & Apply is slow, not broken.** With one 500 MHz core, a service takes 10–20 s to
  reload after Save & Apply, and Wi-Fi changes (radio restart, network reload, reconnect,
  DHCP) can take 30 s or more. Wait before checking whether a change took effect.
* LuCI names the Wi-Fi card "Ubiquiti SR71A": it reports the Atheros reference subsystem
  ID (168c:2082), which OpenWrt's ID table lists under that name. Cosmetic.
* Routing throughput is limited by the single 500 MHz core; enable software flow
  offloading (Network → Firewall) for best results.
* The battery clock may hold D-Link's old time until NTP corrects it.

## Credits

* Device tree base (`dlink_dsr-1000n.dts`, `dlink_dsr-500n-1000n.dtsi`) by Aaro Koskinen, in mainline Linux.
* OpenWrt and the Linux kernel projects.

## License

GPL-2.0 (see `LICENSE`), the same as OpenWrt and the Linux kernel.
