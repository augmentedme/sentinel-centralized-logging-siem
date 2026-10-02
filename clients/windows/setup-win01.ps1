<#
.SYNOPSIS
    Configures the Windows log source VM (win-01).

.DESCRIPTION
    - Enables advanced audit policy so security-relevant events are logged
      (logons, account and group changes, process creation, policy changes)
    - Includes command lines in process creation events (4688)
    - Increases the Security log size
    - Creates a local test account (generates account management events)
    - Installs a failed-logon simulator as a scheduled task (every 30 minutes)

    Designed to run through Azure portal > VM > Run command > RunPowerShellScript
    (runs as SYSTEM, no RDP or file copy needed). Safe to re-run.
#>
$ErrorActionPreference = 'Stop'

function Write-Step($message) { Write-Output "`n==> $message" }

Write-Step 'Enabling advanced audit policy'
$auditSubcategories = @(
    'Logon', 'Logoff', 'Account Lockout', 'Special Logon', 'Other Logon/Logoff Events',
    'Credential Validation', 'User Account Management', 'Security Group Management',
    'Process Creation', 'Audit Policy Change', 'Authentication Policy Change'
)
foreach ($subcategory in $auditSubcategories) {
    auditpol /set /subcategory:"$subcategory" /success:enable /failure:enable | Out-Null
    Write-Output "  $subcategory : success and failure"
}

Write-Step 'Including command lines in process creation events (4688)'
$auditKey = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System\Audit'
New-Item -Path $auditKey -Force | Out-Null
Set-ItemProperty -Path $auditKey -Name 'ProcessCreationIncludeCmdLine_Enabled' -Value 1 -Type DWord

Write-Step 'Setting Security log maximum size to 512 MB'
wevtutil sl Security /ms:536870912

Write-Step 'Creating local test account lab.user (account management events)'
if (-not (Get-LocalUser -Name 'lab.user' -ErrorAction SilentlyContinue)) {
    # Random password that is never stored or displayed: the account only exists
    # to generate 4720 (account created) and 4732 (added to group) events.
    Add-Type -AssemblyName System.Web
    $password = ConvertTo-SecureString ([System.Web.Security.Membership]::GeneratePassword(24, 4)) -AsPlainText -Force
    New-LocalUser -Name 'lab.user' -Password $password -Description 'SIEM lab test account' | Out-Null
    Add-LocalGroupMember -Group 'Remote Desktop Users' -Member 'lab.user'
    Write-Output '  Created lab.user and added it to Remote Desktop Users'
}
else {
    Write-Output '  lab.user already exists'
}

Write-Step 'Installing failed-logon simulator'
$simDir = 'C:\ProgramData\SIEM'
New-Item -ItemType Directory -Path $simDir -Force | Out-Null
$simScript = @'
<#
    win-sim.ps1: generates failed network logons (Event ID 4625) against this
    machine, using usernames that do not exist (so no real account is locked out).
    Normal run: 1-3 failures.  -Burst: 8 failures (triggers the brute-force alert).
#>
param([switch]$Burst)
$fakeUsers = 'administrator', 'admin', 'backup', 'test', 'sqlsvc', 'jdoe', 'scanner'
$count = if ($Burst) { 8 } else { Get-Random -Minimum 1 -Maximum 4 }
for ($i = 1; $i -le $count; $i++) {
    $user = $fakeUsers | Get-Random
    $pass = "Wrong$(Get-Random -Maximum 99999)!"
    net use '\\127.0.0.1\IPC$' "/user:$user" $pass 2>&1 | Out-Null
    net use '\\127.0.0.1\IPC$' /delete /y 2>&1 | Out-Null
}
'@
Set-Content -Path "$simDir\win-sim.ps1" -Value $simScript -Encoding UTF8

$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$simDir\win-sim.ps1`""
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
    -RepetitionInterval (New-TimeSpan -Minutes 30)
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName 'SIEM failed-logon simulator' -Action $action -Trigger $trigger `
    -Principal $principal -Description 'Generates failed logons for SIEM testing' -Force | Out-Null
Write-Output '  Scheduled task "SIEM failed-logon simulator" runs every 30 minutes'

Write-Step 'Running the simulator once now'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$simDir\win-sim.ps1"
$recent = Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4625; StartTime = (Get-Date).AddMinutes(-5) } `
    -ErrorAction SilentlyContinue
Write-Output "  Failed logon events (4625) in the last 5 minutes: $(@($recent).Count)"

Write-Output "`nSetup complete."
