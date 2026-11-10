# RAM-only test boot of OpenWrt on the DSR-1000N over the console (COM1).
# Uses only setenv (NOT saveenv), tftpboot into RAM and bootoctlinux. No flash writes.
# All flash partitions are passed to Linux as read-only. Log: ramboot_log.txt
param([int]$Seconds = 300)
$log = Join-Path $PSScriptRoot 'ramboot_log.txt'
$p = New-Object System.IO.Ports.SerialPort 'COM1',115200,'None',8,'One'
$p.Handshake = 'None'; $p.DtrEnable = $true; $p.RtsEnable = $true
$p.Open()
$script:buf = ''
function Pump([double]$sec) { $t = (Get-Date).AddSeconds($sec); while ((Get-Date) -lt $t) { $c = $p.ReadExisting(); if ($c) { $script:buf += $c; [IO.File]::WriteAllText($log, $script:buf) }; Start-Sleep -Milliseconds 50 } }
function WaitFor([string]$pat, [double]$sec) { $t = (Get-Date).AddSeconds($sec); while ((Get-Date) -lt $t) { $c = $p.ReadExisting(); if ($c) { $script:buf += $c; [IO.File]::WriteAllText($log, $script:buf) }; if ($script:buf -match $pat) { return $true }; Start-Sleep -Milliseconds 50 }; return $false }
function Send([string]$s) { foreach ($ch in $s.ToCharArray()) { $p.Write([string]$ch); Start-Sleep -Milliseconds 3 }; $p.Write("`r") }

# Get to the bootloader prompt (either it is already there, or we catch the next power-on countdown)
$p.Write("`r")
if (-not (WaitFor 'bootloader#' 3)) {
  "Not at the bootloader prompt. Power-cycle the router now; waiting up to 120 s..."
  if (-not (WaitFor 'autoboot' 120)) { $p.Close(); "NO-PROMPT"; exit 1 }
  1..10 | ForEach-Object { $p.Write(' '); Start-Sleep -Milliseconds 50 }
  if (-not (WaitFor 'bootloader#' 5)) { $p.Close(); "NO-PROMPT"; exit 1 }
}
"at bootloader prompt"
$script:buf = ''
Send 'setenv ipaddr 192.168.10.1'; Pump 1
Send 'setenv serverip 192.168.10.100'; Pump 1
$p.Write("`r"); $null = WaitFor 'bootloader#\s*$' 30
$script:buf = ''
Send 'tftpboot 0xaa00000 openwrt-dsr1000n-initramfs.elf'
if (-not (WaitFor 'Bytes transferred|bytes transferred|Retry count exceeded|not found|Error' 240)) { "TFTP timed out"; $p.Close(); exit 1 }
Pump 2
if ($script:buf -notmatch '[Bb]ytes transferred') { "TFTP failed"; $p.Close(); exit 1 }
"image loaded into RAM"
# Same partition names as the flashed layout, but every partition read-only for the test.
Send 'bootoctlinux 0xaa00000 console=ttyS0,115200 mtdparts=phys_mapped_flash:640k(u-boot)ro,29696k(firmware)ro,2M(dlink-config)ro,-(dlink-data)ro'
$null = WaitFor 'Please press Enter to activate this console|Kernel panic|---\[ end' $Seconds
Pump 5
$p.Write("`r"); Pump 2
foreach ($cmd in 'cat /tmp/sysinfo/model /tmp/sysinfo/board_name', 'ip -br link', 'cat /proc/mtd', 'ls /sys/class/leds', 'iw dev; iw phy | head -5', 'dmesg | grep -iE "ath|rtc|usb|eth|mdio|error|fail" | head -40') {
  Send $cmd; Pump 3
}
$p.Close()
"RAMBOOT-DONE log=$log"
