# Watch the DSR-1000N's free GPIO pins (read-only: export + read value) for N seconds and
# report every change, so pressing a button reveals its pin and active level.
# The router shell limits line length, so the watcher is written to /tmp/gw.sh line by line.
param([int]$Seconds = 120)
$log = Join-Path $PSScriptRoot 'gpiowatch_log.txt'
$p = New-Object System.IO.Ports.SerialPort 'COM1',115200,'None',8,'One'; $p.Open()
function Send([string]$s) { foreach ($ch in $s.ToCharArray()) { $p.Write([string]$ch); Start-Sleep -Milliseconds 3 }; $p.Write("`r"); Start-Sleep -Milliseconds 300 }
$p.Write([char]3); Start-Sleep -Milliseconds 300; $p.Write("`r"); Start-Sleep -Milliseconds 500
$null = $p.ReadExisting()
$lines = @(
  'P="0 1 2 3 4 5 6 7 8 12 13 14 15 16 19"',
  'for g in $P; do echo $g > /sys/class/gpio/export 2>/dev/null; done',
  'for g in $P; do eval o$g=$(cat /sys/class/gpio/gpio$g/value); done',
  'for g in $P; do eval echo -n "g$g=\$o$g "; done; echo',
  'echo WATCHING',
  "e=`$((`$(cut -d. -f1 /proc/uptime)+$Seconds))",
  'while [ $(cut -d. -f1 /proc/uptime) -lt $e ]; do',
  ' for g in $P; do v=$(cat /sys/class/gpio/gpio$g/value); eval o=\$o$g',
  '  [ "$v" != "$o" ] && { echo "t=$(cut -d\  -f1 /proc/uptime) gpio$g $o->$v"; eval o$g=$v; }',
  ' done; usleep 100000',
  'done',
  'echo WATCH-DONE'
)
Send 'rm -f /tmp/gw.sh'
foreach ($l in $lines) { Send ("cat >> /tmp/gw.sh <<'EOF'`r" + $l + "`rEOF") }
Send 'sh /tmp/gw.sh'
$o = ''; $end = (Get-Date).AddSeconds($Seconds + 20)
while ((Get-Date) -lt $end -and $o -notmatch '(?m)^WATCH-DONE') { $c = $p.ReadExisting(); if ($c) { $o += $c; [IO.File]::WriteAllText($log, $o) }; Start-Sleep -Milliseconds 100 }
$p.Close()
($o -split "`n") | Where-Object { $_ -match '^g\d|^WATCHING|^t=|^WATCH-DONE' }
