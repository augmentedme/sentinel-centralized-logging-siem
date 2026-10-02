<#
.SYNOPSIS
    Sends a burst of failed logins and sensitive-path probes to web-01 from
    this workstation, so the alerts fire with an external source IP.

.DESCRIPTION
    For end-to-end testing of the brute-force and web scanning analytics rules.
    Only run this against your own web-01 VM.

.EXAMPLE
    .\simulator\attack-burst.ps1 -Target 20.211.10.10
#>
param(
    [Parameter(Mandatory)]
    [string]$Target
)

$base = "http://$Target"
$users = 'admin', 'root', 'test', 'administrator', 'jsmith'
$paths = '/.env', '/.git/config', '/wp-admin/', '/wp-login.php', '/phpmyadmin/',
         '/xmlrpc.php', '/admin.php', '/server-status', '/.aws/credentials', '/config.json'

Write-Host "Sending 12 failed logins to $base/login"
for ($i = 1; $i -le 12; $i++) {
    $body = @{ username = ($users | Get-Random); password = "Wrong$(Get-Random -Maximum 9999)" }
    try { Invoke-WebRequest -Uri "$base/login" -Method Post -Body $body -UseBasicParsing | Out-Null }
    catch { }  # 401 responses are expected
}

Write-Host "Sending 15 sensitive-path probes"
for ($i = 1; $i -le 15; $i++) {
    try { Invoke-WebRequest -Uri ($base + ($paths | Get-Random)) -UseBasicParsing | Out-Null }
    catch { }  # 404 responses are expected
}

Write-Host "Done. Alerts should appear in Sentinel within about 15-25 minutes."
