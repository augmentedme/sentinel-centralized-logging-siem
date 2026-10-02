# 07 · Retention

## Configuration options

Every retention setting is a Terraform variable or attribute. Change the value, run `terraform plan`, review, then `terraform apply`.

| Option | Where it is set | Effect |
|---|---|---|
| Workspace default retention | `workspace_retention_days` in `terraform/variables.tf` (attribute `retention_in_days` on the workspace, `main.tf`) | Interactive (hot) retention for any table without its own setting. 90 days is included with Microsoft Sentinel at no extra retention charge. Range 30 to 730 days. |
| Per-table interactive retention | `table_retention` and `custom_table_retention` maps, `interactive` value (`tables.tf`) | How long a table stays fully queryable for rules, workbooks and hunting. Can be shorter or longer than the workspace default. |
| Per-table total retention | Same maps, `total` value | Interactive plus long-term (cold) retention. Data past the interactive period moves to low-cost long-term storage until the total is reached. Up to 12 years. |
| Table plan | `plan` on the custom tables (`tables.tf`) | `Analytics` (full features, used here), `Basic` or `Auxiliary` (low-cost ingestion with reduced query capability). |
| Daily ingestion cap | `daily_cap_gb` | Cost safety net. Collection pauses for the rest of the day once reached, so it is set well above normal volume. |

## Current settings

| Table | Interactive (hot) | Total (hot + cold) | Reason |
|---|---|---|---|
| `SecurityEvent` | 90 days | 365 days | Windows authentication and account changes; key for investigations |
| `SigninLogs` | 90 days | 365 days | Identity is the most targeted control plane |
| `AuditLogs` | 90 days | 365 days | Directory changes (users, groups, roles) |
| `AzureActivity` | 90 days | 365 days | Cloud control-plane changes |
| `WebAppAudit_CL` | 90 days | 365 days | Application security audit trail |
| `Syslog` | 90 days | 180 days | Operational and SSH data; lower long-term value |
| `Event` | 90 days | 180 days | System errors and warnings; operational |
| `NginxAccess_CL` | 30 days | 180 days | High volume; value drops quickly after 30 days |
| Other tables | 90 days (workspace default) | 90 days | Not individually managed |

Values above 730 days for total retention must use one of Azure's supported long-term values (for example 1095, 2556 or 4383 days).

To check the effective values: **Portal > Log Analytics workspaces > law-siem > Tables**, or from a workstation:

```powershell
az monitor log-analytics workspace table show -g rg-siem-demo --workspace-name law-siem -n SecurityEvent --query "{plan:plan, interactive:retentionInDays, total:totalRetentionInDays}"
```

## Hot, warm and cold strategy

| Tier | Implementation | Characteristics | Used for |
|---|---|---|---|
| **Hot** | Analytics plan, interactive retention | Fast full KQL; analytics rules, workbooks and hunting all work. Highest cost per GB. | Detection and active investigations. All tables here (in use). |
| **Warm** | Basic or Auxiliary table plan | Much cheaper ingestion; reduced KQL and slower queries; not suited to scheduled analytics rules in this design. | High-volume, low-value data such as verbose access or debug logs (option, not used: the web scanning rule reads `NginxAccess_CL`). |
| **Cold** | Long-term retention (total retention beyond interactive) | Very low storage cost; not directly queryable. Accessed with a **search job** (results copied into a new hot table) or a **restore** (a time range made hot again temporarily). | Compliance, look-back investigations, incidents discovered months later (in use). |
| **Archive outside the SIEM** | Workspace data export rule to a storage account, with blob lifecycle (Hot > Cool > Cold > Archive tiers) and an immutability policy | Cheapest per GB; independent of the SIEM; tamper-evident. | Legal hold, regulatory evidence, very long retention (option, documented, not deployed). |

## Choosing retention for a client

Retention is set per table from four questions, never as one number for everything:

1. **Detection value.** How far back do analytics rules and hunting need to look? This sets the interactive period.
2. **Investigation needs.** Breaches are often discovered months after initial access. Identity, endpoint and cloud control-plane logs justify a year or more of total retention.
3. **Regulation and contracts.** For example NZISM, the Public Records Act 2005 for public sector agencies, PCI DSS (at least 12 months, 3 immediately available) or client contracts. These set the minimum total retention.
4. **Cost.** Volume multiplied by tier price. Verbose, low-value sources go to cheaper plans or shorter retention; their summaries can be kept instead.

## Accessing cold data

When data has moved past its interactive period:

- **Search job:** **Portal > Log Analytics workspaces > law-siem > Logs**, switch the query mode to **Search job**. Runs a query over long-term data asynchronously and writes the results to a new table (suffix `_SRCH`) that can then be queried normally.
- **Restore:** **Log Analytics workspace > Tables > (table) > Restore**. Brings a time range back into hot storage for intensive investigation, then is removed.

Both carry their own charges, which is the trade-off for low storage cost.
