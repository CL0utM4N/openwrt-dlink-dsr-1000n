# Upload a shell script to the router's /tmp over the console (short heredoc lines, to stay
# under the shell's line-length limit), run it, and capture output until its end marker.
param([Parameter(Mandatory)][string]$Script, [int]$Timeout = 120, [string]$Out = '')
$lines = Get-Content $Script
$p = New-Object System.IO.Ports.SerialPort 'COM1',115200,'None',8,'One'; $p.Open()
function Send([string]$s) { foreach ($ch in $s.ToCharArray()) { $p.Write([string]$ch); Start-Sleep -Milliseconds 2 }; $p.Write("`r"); Start-Sleep -Milliseconds 150 }
$p.Write("`r"); Start-Sleep -Milliseconds 400; $null = $p.ReadExisting()
Send 'rm -f /tmp/rs.sh'
foreach ($l in $lines) { if ($l.Length -gt 400) { throw "line too long: $l" }; Send ("cat >> /tmp/rs.sh <<'EOF'`r" + $l + "`rEOF") }
Start-Sleep -Milliseconds 300; $null = $p.ReadExisting()
Send 'sh /tmp/rs.sh; echo RS-END'
$o = ''; $end = (Get-Date).AddSeconds($Timeout)
while ((Get-Date) -lt $end -and $o -notmatch '(?m)^RS-END') { $c = $p.ReadExisting(); if ($c) { $o += $c }; Start-Sleep -Milliseconds 100 }
$p.Close()
$o = ($o -split "`n" | Where-Object { $_ -notmatch 'rs\.sh; echo RS-END|^RS-END' }) -join "`n"
if ($Out) { [IO.File]::WriteAllText($Out, $o) }
$o
