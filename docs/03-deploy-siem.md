# 03 · Deploy the SIEM platform

This step builds the logging system itself with Terraform. Client VMs are onboarded afterwards (see 04).

## What gets created

| Resource | Name | Purpose |
|---|---|---|
| Resource group | `rg-siem-demo` | Holds everything |
| Log Analytics workspace | `law-siem` | Log store, 90-day default retention, daily cap |
| Sentinel onboarding | on `law-siem` | Enables Microsoft Sentinel |
| Custom tables | `NginxAccess_CL`, `WebAppAudit_CL` | Destinations for file-based logs |
| Data Collection Endpoint | `dce-siem` | Ingestion endpoint for custom log files |
| DCR | `dcr-linux-syslog` | Syslog facilities auth, authpriv, daemon, syslog, local0 |
| DCR | `dcr-linux-customlogs` | Nginx JSON access log and web app audit log |
| DCR | `dcr-windows-security` | Filtered Security events and System errors/warnings |
| Diagnostic setting | `activity-log-to-sentinel` | Subscription Activity Log to the workspace |
| Table retention | built-in and custom tables | Hot and long-term retention per table |
| Analytics rules | brute force, web scanning | Alerts that create Sentinel incidents |
| Budget | `budget-siem-demo` | Email alerts at 50% actual and 90% forecast spend |

## Steps

**1. Sign in and select the subscription.**

```powershell
az login
az account show --query "{name:name, id:id}" -o table
```

**2. Give Terraform the subscription ID through an environment variable** (keeps it out of the repo):

```powershell
$env:ARM_SUBSCRIPTION_ID = az account show --query id -o tsv
```

This lasts for the current PowerShell window. Repeat it in each new window.

**3. Create your variables file.**

```powershell
cd terraform
Copy-Item terraform.tfvars.example terraform.tfvars
notepad terraform.tfvars
```

Set `alert_email`. Adjust `budget_start_date` to the first day of the current month. `terraform.tfvars` is git-ignored.

**4. Initialise, review and apply.**

```powershell
terraform init
terraform fmt -recursive
terraform validate
terraform plan -out tfplan
terraform apply tfplan
```

Read the plan before applying: every resource listed should match the table above.

**5. Verify in the portal.**

- **Microsoft Sentinel** lists workspace `law-siem`.
- **Sentinel > Analytics > Active rules** shows the two rules.
- **Log Analytics workspace > Tables** shows `NginxAccess_CL` and `WebAppAudit_CL` with their retention values.
- **Monitor > Data Collection Rules** shows the three DCRs.

## Changing settings later

All tunable values are variables. Change them in `terraform.tfvars` and re-run `terraform plan` then `terraform apply`. For example, to lower the brute-force threshold:

```hcl
bruteforce_threshold = 3
```

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `MissingSubscriptionRegistration` | A resource provider is not registered. See 02 Prerequisites. |
| Error on `azurerm_log_analytics_workspace_table` for `SigninLogs` or `AuditLogs` | The table is not available yet. Set `manage_builtin_table_retention = false`, apply, connect Entra ID, then set it back to `true` and apply again. |
| Budget creation fails | Some subscription offers do not support budgets through the API. Set `create_budget = false` and create the budget in Cost Management instead. |
| Sentinel data connector page shows "Not connected" for Syslog or Windows events | Expected: the DCRs were created by Terraform rather than the connector wizard. Data still flows; confirm with a query. |

## Removing everything

Delete the client VMs (and their disks and network interfaces) in the portal first. Terraform will not delete a resource group that still contains resources it did not create. Then run:

```powershell
terraform destroy
```
