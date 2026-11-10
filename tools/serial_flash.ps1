# Flash OpenWrt to the DSR-1000N from U-Boot over the console (COM1).
# Every check before the erase aborts with nothing written. Log: flash_log.txt
#  1 stop at U-Boot   2 tftpboot image to RAM   3 CRC32 of RAM copy == file
#  4 set + read back the OpenWrt boot variables (owrt_load, owrt_boot), no saveenv yet
#  5 erase firmware area 0xbdca0000-0xbf99ffff (same range as D-Link's firm_flash)
#  6 copy RAM -> flash   7 CRC32 of flash == file
#  8 keep D-Link's bootcmd as dlink_bootcmd, set the OpenWrt bootcmd, saveenv
#  9 reset and capture the first boot
param([string]$Image = 'openwrt-dsr1000n-sysupgrade.bin')
$ErrorActionPreference = 'Stop'
$log = Join-Path $PSScriptRoot 'flash_log.txt'
$file = Join-Path $PSScriptRoot "tftp\$Image"
$bytes = [IO.File]::ReadAllBytes($file)
$size = $bytes.Length
$crc = (& python -I -c "import zlib,sys; print('%08x' % (zlib.crc32(open(sys.argv[1],'rb').read()) & 0xffffffff))" $file).Trim()
$sizeHex = '0x{0:x}' -f $size
"image $Image size $size ($sizeHex) crc32 $crc"

$p = New-Object System.IO.Ports.SerialPort 'COM1',115200,'None',8,'One'
$p.Handshake = 'None'; $p.DtrEnable = $true; $p.RtsEnable = $true; $p.Open()
$script:all = ''; $script:buf = ''
function Pull { $c = $p.ReadExisting(); if ($c) { $script:buf += $c; $script:all += $c; [IO.File]::WriteAllText($log, $script:all) } }
function WaitFor([string]$pat, [double]$sec) { $t = (Get-Date).AddSeconds($sec); while ((Get-Date) -lt $t) { Pull; if ($script:buf -match $pat) { return $true }; Start-Sleep -Milliseconds 50 }; return $false }
function Send([string]$s) { $script:buf = ''; foreach ($ch in $s.ToCharArray()) { $p.Write([string]$ch); Start-Sleep -Milliseconds 4 }; $p.Write("`r") }
function Cmd([string]$s, [double]$sec = 10) { Send $s; if (-not (WaitFor 'bootloader#\s*$' $sec)) { throw "timeout waiting for prompt after: $s" }; return $script:buf }
function Abort([string]$why) { "ABORT (nothing erased): $why"; $p.Close(); exit 1 }

# 1. get to U-Boot: if OpenWrt is running, reboot it and catch the countdown
$p.Write("`r")
if (-not (WaitFor 'bootloader#' 3)) {
  $p.Write("reboot`r")
  if (-not (WaitFor 'autoboot' 120)) { Abort 'no U-Boot countdown seen' }
  1..10 | ForEach-Object { $p.Write(' '); Start-Sleep -Milliseconds 50 }
  if (-not (WaitFor 'bootloader#' 5)) { Abort 'no U-Boot prompt' }
}
"1 at U-Boot prompt"
$null = Cmd 'setenv ipaddr 192.168.10.1'
$null = Cmd 'setenv serverip 192.168.10.100'

# 2. load image into RAM
$o = Cmd "tftpboot 0xaa00000 $Image" 240
if ($o -notmatch "Bytes transferred = $size ") { Abort "tftp size mismatch: $o" }
"2 image in RAM ($size bytes)"

# 3. CRC of RAM copy
$o = Cmd "crc32 0xaa00000 $sizeHex" 60
if ($o -notmatch "==> $crc") { Abort "RAM crc mismatch (want $crc): $o" }
"3 RAM CRC32 matches $crc"

# 4. boot variables (no ';' escaping needed: bootcmd = "run owrt_load owrt_boot"), not saved yet
$parts = 'mtdparts=phys_mapped_flash:640k(u-boot)ro,29696k(firmware),2M(dlink-config)ro,-(dlink-data)ro'
$load = 'cp.b 0xbdca0000 0xaa00000 0x1000000'
$bootl = "bootoctlinux 0xaa00000 console=ttyS0,115200 $parts"
$null = Cmd "setenv owrt_load $load"
$null = Cmd "setenv owrt_boot $bootl"
$o = Cmd 'printenv owrt_load'
if ($o -notmatch [regex]::Escape("owrt_load=$load")) { Abort "owrt_load did not round-trip: $o" }
$o = Cmd 'printenv owrt_boot'
if ($o -notmatch [regex]::Escape("owrt_boot=$bootl")) { Abort "owrt_boot did not round-trip: $o" }
"4 boot variables verified (not saved yet)"

# 5. erase firmware area (point of no return for the D-Link firmware; backup is on the PC)
"5 erasing 0xbdca0000-0xbf99ffff ..."
$o = Cmd 'erase 0xbdca0000 0xbf99ffff' 900
if ($o -notmatch 'Erased|done') { "WARNING erase output: $o" }

# 6. write
"6 writing $size bytes ..."
$o = Cmd "cp.b 0xaa00000 0xbdca0000 $sizeHex" 1200
# 7. verify flash
$o = Cmd "crc32 0xbdca0000 $sizeHex" 60
if ($o -notmatch "==> $crc") { "FLASH CRC MISMATCH (want $crc): $o"; "bootcmd NOT changed. Re-run the write, or restore from backup."; $p.Close(); exit 2 }
"7 flash CRC32 matches $crc"

# 8. boot command
$null = Cmd 'setenv dlink_bootcmd bootFirmware'
$null = Cmd 'setenv bootcmd run owrt_load owrt_boot'
$o = Cmd 'printenv bootcmd'
if ($o -notmatch 'bootcmd=run owrt_load owrt_boot') { "bootcmd not set as expected: $o"; $p.Close(); exit 3 }
$o = Cmd 'saveenv' 60
"8 bootcmd saved: $((Cmd 'printenv bootcmd') -split "`n" | Select-String 'bootcmd=' | Select-Object -First 1)"

# 9. first boot
$script:buf = ''; $p.Write("reset`r")
$null = WaitFor 'Please press Enter to activate this console|Kernel panic|---\[ end|VFS: Unable' 300
Start-Sleep 3; Pull
$p.Close()
"9 FLASH-DONE log=$log"
