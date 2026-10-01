# 02 · Prerequisites

## Accounts

| Account | Purpose | Notes |
|---|---|---|
| Azure subscription | Hosts Sentinel and the client VMs | A free trial works. At least 4 vCPUs of quota in the target region. |
| Microsoft Entra ID P2 (or P1) | Required to export Entra sign-in logs | Free 30-day trial from the Entra admin center. |
| Okta Integrator (free) | SaaS log source | developer.okta.com |

## Workstation tools

Install on Windows with winget:

```powershell
winget install Git.Git Microsoft.VisualStudioCode Microsoft.AzureCLI Hashicorp.Terraform
```

Also install:

- **gitleaks** (secret scanner): download the Windows release from the gitleaks GitHub releases page and place `gitleaks.exe` in a folder on your `PATH`.
- **checkov** (IaC scanner, optional): `pip install checkov`

Verify:

```powershell
git --version
az version
terraform version
gitleaks version
```

## Register Azure resource providers

New subscriptions may not have every provider registered. Run once:

```powershell
az login
foreach ($p in 'Microsoft.OperationalInsights','Microsoft.OperationsManagement','Microsoft.SecurityInsights','Microsoft.Insights','Microsoft.Compute','Microsoft.Network','Microsoft.Consumption') {
    az provider register --namespace $p
}
```

Registration takes a few minutes. Check with `az provider show -n Microsoft.SecurityInsights --query registrationState`.

## SSH key for the Linux VM

```powershell
ssh-keygen -t ed25519 -C "web-01"
```

The private key stays in `~/.ssh` on your workstation. Only the `.pub` file is pasted into Azure. Neither file goes into this repository.

## Your public IP

SSH and RDP rules are restricted to the administrator's public IP. Find it with:

```powershell
(Invoke-RestMethod https://api.ipify.org)
```
