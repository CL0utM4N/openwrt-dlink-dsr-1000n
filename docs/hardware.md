# D-Link DSR-1000N (rev A1): hardware notes

Everything here was read from a running unit (U-Boot console, Linux sysfs, MDIO
registers), not taken from a datasheet. Board revision reported by U-Boot:
`CUST_DSR1000 board revision major:2, minor:0`.

## SoC, memory, flash

| Part | Details |
|---|---|
| SoC | Cavium Octeon Plus CN5010-SCP pass 1.1, **one** cnMIPS64 core @ 500 MHz, big-endian, no FPU |
| RAM | 256 MB DDR2 (2x Samsung K4T1G164QF), DDR clock 200 MHz |
| Flash | 32 MB parallel NOR (MXIC MX29GL256EH), CFI/AMD command set, 128 KB sectors, at 0xBDC00000 |
| RTC | Dallas DS1337 on the Octeon TWSI (I2C) bus, address 0x68 |
| Console | Front RJ45 "Console", RS-232, 115200 8N1, Cisco pinout (pin 3 = router TX, pin 6 = router RX, pins 4/5 = GND) |
| Bootloader | U-Boot 1.1.1 (Cavium SDK, 2010), `bootdelay=3`, any key stops autoboot |

## Ethernet

The Octeon has one RGMII interface with three ports (`eth0`..`eth2`).

| Linux | Connects to | Front panel |
|---|---|---|
| `eth0` | BCM53115 switch, IMP port 8, fixed 1 Gb/s RGMII | LAN1..LAN4 = switch ports 0..3 (LAN1 = port 0, verified), WAN1 = switch port 4 |
| `eth1` | BCM53115 switch port 5, fixed 1 Gb/s RGMII | D-Link's WAN path (port 4 <-> 5). **Unused** by this port; b53 disables port 5 |
| `eth2` (`wan2`) | Broadcom BCM5481 PHY (ID 0x0143bca2) at MDIO address 8 | WAN2/DMZ |

* Switch: Broadcom **BCM53115** rev 8, managed over MDIO through its pseudo-PHY at
  address **30 (0x1e)** on the Octeon SMI bus. Internal PHYs of ports 0..4 answer at MDIO
  addresses 0..4 (ID 0x0143bf88).
* RGMII delays: U-Boot leaves `RGMII_CTRL_IMP` (page 0x00, reg 0x60) = 0x00 (no switch-side
  delays). In the Linux b53 driver, for the BCM53115, `phy-mode = "rgmii"` turns **both**
  switch-side delays **on**; `"rgmii-id"` leaves them off. The DTS therefore uses `rgmii-id`.
* U-Boot programs port-based VLANs at power-on (LAN 0-3 + 8, WAN 4 + 5). The b53 driver
  replaces this with proper DSA isolation.
* With Broadcom tags on the IMP port, the Octeon PIP flags every frame as an 802.3 length
  error (error code 10), because the tag sits where the EtherType is expected. The frames
  are fine; patch 163 stops the driver from dropping them.

## GPIO (Octeon GPIO 0..19)

| GPIO | Function | Polarity |
|---|---|---|
| 7 | WPS button | active low |
| 8 | Reset button | active low |
| 9 | LED usb1 | active low |
| 10 | LED usb2 | active low |
| 11 | LED wps | active low |
| 17 | LED 5g | active low |
| 18 | LED 2.4g | active low |

Buttons were found by watching all free GPIOs while pressing them (tools/serial_gpiowatch.ps1).

## PCI and Wi-Fi

* Plain 32-bit PCI at 33 MHz (no PCIe) with one **mini-PCI** slot.
* Stock card: Atheros **AR9160** + AR5133 radio (168c:0027, subsystem 168c:2082, the Atheros
  reference ID, which LuCI's table names "Ubiquiti SR71A"). 802.11a/b/g/n, 3 chains, one band at a time. Driver: ath9k.

## USB

One USB 2.0 host port, Octeon `octeon-hcd` controller, with a 2-port hub behind it.

## Flash layout

### Stock (D-Link)

| Offset | Size | Contents |
|---|---|---|
| 0x0000000 | 640 KB | U-Boot (first 4 sectors write-protected) |
| 0x00A0000 | 9 MB | D-Link kernel (firmware image starts with a 0xB4-byte D-Link header, ELF at +0x200) |
| 0x09A0000 | 20 MB | D-Link rootfs |
| 0x1DA0000 | 2 MB | D-Link configuration ("AppConfig") |
| 0x1FA0000 | 384 KB | Product data at 0x1FC0000, U-Boot environment at 0x1FE0000 (last sector write-protected) |

Product data (`getpd` in U-Boot) at 0x1FC0000: serial at +0x20, base MAC as 12 ASCII hex
digits at **+0x64**. D-Link's U-Boot itself uses the default MAC 00:de:ad:20:75:00.

### OpenWrt (this port)

Passed to the kernel by U-Boot (`mtdparts=`):

| Partition | Offset | Size | Notes |
|---|---|---|---|
| `u-boot` | 0x0000000 | 640 KB | read-only |
| `firmware` | 0x00A0000 | 29 MB | stripped ELF kernel, squashfs at the next 128 KB boundary, jffs2 overlay after it; split at boot by `mtdsplit_elf` |
| `dlink-config` | 0x1DA0000 | 2 MB | D-Link config, left untouched, read-only |
| `dlink-data` | 0x1FA0000 | 384 KB | product data + U-Boot env, read-only |

MAC addresses: LAN = base, WAN = base+1, WAN2 = base+2, Wi-Fi = base+3.

## U-Boot environment used by this port

```
owrt_load=cp.b 0xbdca0000 0xaa00000 0x1000000
owrt_boot=bootoctlinux 0xaa00000 console=ttyS0,115200 mtdparts=phys_mapped_flash:640k(u-boot)ro,29696k(firmware),2M(dlink-config)ro,-(dlink-data)ro
bootcmd=run owrt_load owrt_boot
dlink_bootcmd=bootFirmware        (D-Link's original, kept for going back)
```

`bootcmd` uses `run` with two variables instead of a `;`-separated command, which avoids
any escaping differences in this old U-Boot. D-Link's `bootFirmware` checks a D-Link
checksum, so it cannot boot OpenWrt; its `boot_firm` only copies 9 MB, too little for an
unmodified OpenWrt kernel (~10.5 MB here).
