<#
.SYNOPSIS
    Security and quality checks to run before every 'git push'.

.DESCRIPTION
    1. terraform fmt      - consistent formatting
    2. terraform validate - configuration is valid
    3. gitleaks           - no secrets in committed history or in staged changes
    4. checkov            - infrastructure-as-code security scan (optional)

    Run from the repo root with the Python venv (containing checkov) active.

.EXAMPLE
    .\scripts\pre-push-checks.ps1
    .\scripts\pre-push-checks.ps1 -SkipCheckov
#>
param(
    [switch]$SkipCheckov
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot
$failed = @()

function Invoke-Check {
    param([string]$Name, [scriptblock]$Command)
    Write-Host "`n=== $Name ===" -ForegroundColor Cyan

    # Sentinel value: if the tool never runs, the exit code stays 999 and the
    # check fails, instead of silently reusing the previous command's result.
    $global:LASTEXITCODE = 999
    try {
        & $Command
    }
    catch {
        Write-Host $_ -ForegroundColor Red
    }

    if ($LASTEXITCODE -eq 999) {
        Write-Host "FAILED: $Name did not run. Is the tool installed and on PATH (or the venv active)?" -ForegroundColor Red
        $script:failed += $Name
    }
    elseif ($LASTEXITCODE -ne 0) {
        Write-Host "FAILED: $Name (exit code $LASTEXITCODE)" -ForegroundColor Red
        $script:failed += $Name
    }
    else {
        Write-Host "PASSED: $Name" -ForegroundColor Green
    }
}

Invoke-Check 'terraform fmt' { terraform -chdir=terraform fmt -check -recursive }
Invoke-Check 'terraform validate' { terraform -chdir=terraform validate -no-color }
# 'detect' scans commits already made; 'protect --staged' scans what is about
# to be committed. Both are needed: run this script after 'git add'.
Invoke-Check 'gitleaks: commit history' { gitleaks detect --source . --no-banner --redact -v }
Invoke-Check 'gitleaks: staged changes' { gitleaks protect --staged --source . --no-banner --redact -v }

if (-not $SkipCheckov) {
    if (-not $env:VIRTUAL_ENV) {
        Write-Host "`nWarning: no Python venv is active, so checkov may not be found." -ForegroundColor Yellow
    }
    # 'python -m' avoids the Windows .py file-association problem.
    Invoke-Check 'checkov (IaC scan)' { python -m checkov.main -d terraform --framework terraform --compact --quiet }
}

Write-Host ''
if ($failed.Count -gt 0) {
    Write-Host "Checks failed: $($failed -join ', '). Fix before pushing." -ForegroundColor Red
    exit 1
}
Write-Host 'All checks passed. Safe to push.' -ForegroundColor Green