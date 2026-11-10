# Send shell commands to the router's console (COM1) and print the replies.
param([Parameter(Mandatory)][string[]]$Commands, [double]$Wait = 3)
$p = New-Object System.IO.Ports.SerialPort 'COM1',115200,'None',8,'One'
$p.Handshake = 'None'; $p.Open()
$null = $p.ReadExisting(); $p.Write("`r"); Start-Sleep -Milliseconds 500
$out = $p.ReadExisting()
foreach ($c in $Commands) {
  foreach ($ch in $c.ToCharArray()) { $p.Write([string]$ch); Start-Sleep -Milliseconds 2 }
  $p.Write("`r")
  $t = (Get-Date).AddSeconds($Wait); while ((Get-Date) -lt $t) { $out += $p.ReadExisting(); Start-Sleep -Milliseconds 50 }
}
$p.Close()
$out
