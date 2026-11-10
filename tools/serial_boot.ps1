# Capture the router's boot on COM1. If the U-Boot countdown appears, stop it and run the
# read-only commands printenv / version / flinfo, then save everything to boot_log.txt.
param([int]$Seconds = 180)
$log = Join-Path $PSScriptRoot 'boot_log.txt'
$p = New-Object System.IO.Ports.SerialPort 'COM1',115200,'None',8,'One'
$p.Handshake = 'None'; $p.DtrEnable = $true; $p.RtsEnable = $true
$p.Open()
$buf = ''; $stopped = $false; $done = $false
$end = (Get-Date).AddSeconds($Seconds)
"LISTENING $(Get-Date -Format T)"
while ((Get-Date) -lt $end -and -not $done) {
  $chunk = $p.ReadExisting()
  if ($chunk) { $buf += $chunk; [IO.File]::WriteAllText($log, $buf) }
  if (-not $stopped -and $buf -match 'autoboot') {
    1..10 | ForEach-Object { $p.Write(' '); Start-Sleep -Milliseconds 50 }
    Start-Sleep -Milliseconds 500; $p.Write("`r"); Start-Sleep -Milliseconds 500
    $stopped = $true
    foreach ($cmd in 'getpd','printenv') {
      $p.Write("$cmd`r"); $t = (Get-Date).AddSeconds(4)
      while ((Get-Date) -lt $t) { $buf += $p.ReadExisting(); Start-Sleep -Milliseconds 100 }
    }
    [IO.File]::WriteAllText($log, $buf); $done = $true
  }
  Start-Sleep -Milliseconds 30
}
$p.Close()
"stopped_at_prompt=$stopped bytes=$($buf.Length) log=$log"
