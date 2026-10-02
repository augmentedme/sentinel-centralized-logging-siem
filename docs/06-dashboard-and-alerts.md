# 06 · Dashboard and alerts

Both are defined as code and deployed by Terraform:

| Item | Definition | Deployed by |
|---|---|---|
| Dashboard: **SIEM Security Overview** workbook | `workbooks/security-overview.json` | `terraform/workbook.tf` |
| Alert: **Brute-force login attempts across sources** | `detections/bruteforce-cross-source.kql` | `terraform/detections.tf` |
| Alert: **Web vulnerability scanning** | `detections/web-vulnerability-scanning.kql` | `terraform/detections.tf` |
| Hunting query: failed logins from all sources | `detections/hunting/auth-failures-all-sources.kql` | run manually |

Each step says **where** to run it: **Workstation** (VS Code terminal on your Windows machine, repo root), **web-01** (SSH session), or **Defender** (security.microsoft.com).

---

## Dashboard configuration

The workbook has a **Time range** parameter (1 hour to 14 days, default 7 days) that drives every panel.

| Panel | Visualisation | What it answers |
|---|---|---|
| Ingestion health | Table with status icons | Is every source still sending? Flags a source as "Check source" when it has been silent longer than expected: 60 minutes for continuous sources, 24 hours for Entra ID and Okta, which only log when someone signs in. |
| Events per source over time | Time chart | Volume trend for all eight sources. |
| Failed logins by source over time | Time chart | Authentication failures from the web app, Linux SSH, Windows, Entra ID and Okta in one view. |
| Top 10 source IPs with failed logins | Table | Which IPs are attacking, against which sources and how many accounts. |
| Web responses by status class over time | Time chart | 2xx/3xx/4xx/5xx trend; spikes in 4xx often indicate scanning. |
| Most probed sensitive paths | Table | What scanners are looking for (`/.env`, `/wp-admin`, ...). |
| Web application security events | Bar chart | Logins, failures, access denials and admin access in the Staff Portal. |
| Sentinel incidents | Table | Incidents raised by this project's analytics rules. |

**To change the dashboard:** edit it in the portal (**Edit**), then **Advanced editor > Gallery Template**, copy the JSON over `workbooks/security-overview.json`, and run `terraform apply`. Leave `fallbackResourceIds` empty in the file; Terraform injects the workspace ID.

## Alert configuration

| Setting | Brute force | Web scanning |
|---|---|---|
| Logic | One source IP with `bruteforce_threshold` (5) or more failed logins across all authentication sources | One source IP requesting `webscan_threshold` (10) or more known-sensitive paths |
| Sources | Web app audit log, Linux SSH, Windows 4625, Entra ID, Okta | Nginx access log |
| Runs every | 5 minutes (`bruteforce_frequency_minutes`) | 5 minutes (`webscan_frequency_minutes`) |
| Looks back | 15 minutes (`bruteforce_window_minutes`) | 15 minutes (`webscan_window_minutes`) |
| Severity | Medium | Low |
| MITRE ATT&CK | Credential Access, T1110 Brute Force | Reconnaissance, T1595 Active Scanning |
| Entity mapping | IP address (`SourceIP`) | IP address (`SourceIP`) |
| Alert title | `Brute-force login attempts from {{SourceIP}}` | `Web vulnerability scanning from {{SourceIP}}` |
| Incident grouping | Alerts with the same IP within 1 hour are grouped into one incident | Same |

**Why the look-back is longer than the run frequency:** logs can arrive a few minutes after the event happens. A 15-minute window evaluated every 5 minutes means a late event is still inside the window on a later run. Incident grouping stops the overlap from creating duplicate incidents.

**Why one rule covers five sources:** each source records failed logins differently (a JSON field, an sshd message, Event ID 4625, an Entra result code, an Okta outcome). The query normalises them into one schema (time, source, account, IP) before counting, so a password-spraying attacker who rotates between services is still caught.

**To tune:** change the variables in `terraform/terraform.tfvars` (for example `bruteforce_threshold = 8`) and run `terraform apply`. Known noisy IPs could be excluded with a watchlist (listed in improvements).

---

## Steps

### Step 1: Confirm the Okta field names (Defender)

The brute-force rule reads four Okta columns. **Investigation & response > Hunting > Advanced hunting**, run:

```kusto
OktaV2_CL
| getschema
| where ColumnName in ("EventOriginalType", "EventResult", "ActorUsername", "SrcIpAddr")
| project ColumnName, ColumnType
```

Expected: **4 rows**. Then confirm failed Okta sign-ins are visible:

```kusto
OktaV2_CL
| where EventOriginalType == "user.session.start"
| project TimeGenerated, ActorUsername, SrcIpAddr, EventResult
| order by TimeGenerated desc
| take 20
```

Expected: rows with `EventResult` showing failures and successes for your test user.

### Step 2: Deploy the dashboard and updated rules (Workstation)

```powershell
$env:ARM_SUBSCRIPTION_ID = az account show --query id -o tsv
cd terraform
terraform validate
terraform plan -out tfplan
```

Expected plan: **1 to add** (the workbook) and **2 to change** (the two rules). Then:

```powershell
terraform apply tfplan
cd ..
```

### Step 3: Open the dashboard (Defender)

**Microsoft Sentinel > Threat management > Workbooks > My workbooks > SIEM Security Overview > View saved workbook.**

Every panel should show data (the incidents panel stays empty until Step 4). Try switching the time range between 4 hours and 7 days.

### Step 4: Fire both alerts (Workstation)

Find web-01's public IP (**Portal > web-01 > Overview**), then:

```powershell
.\simulator\attack-burst.ps1 -Target <web-01-public-ip>
```

This sends 12 failed logins and 15 sensitive-path probes from your own IP, so the incidents show an external attacker address.

Optional, to add Linux SSH and Windows failures to the same window:

- **web-01:** `sudo siem-sim burst`
- **Portal > win-01 > Run command > RunPowerShellScript:** `& 'C:\ProgramData\SIEM\win-sim.ps1' -Burst`

### Step 5: Investigate the incidents (Defender)

Within about 10 to 20 minutes:

**Investigation & response > Incidents & alerts > Incidents.** Expected:

- `Brute-force login attempts from <your IP>` (Medium)
- `Web vulnerability scanning from <your IP>` (Low)

Open each one. Check the IP entity, the alert's **query results** (FailedAttempts, Sources, Accounts / Probes, SamplePaths), and the MITRE technique.

### Step 6: Capture evidence (Workstation)

Take screenshots of the dashboard and both incidents. Save them as:

- `docs/images/dashboard.png`
- `docs/images/incident-bruteforce.png`
- `docs/images/incident-webscan.png`

Home and public IP addresses are redacted before committing. Only `127.0.0.1` and private addresses are left visible..

## Tuning an alert threshold

All thresholds and timings are Terraform variables, so tuning is a reviewed, version-controlled change rather than a portal edit. Example: make the brute-force rule more sensitive.

1. **Workstation:** in `terraform/terraform.tfvars`, add `bruteforce_threshold = 3`.
2. **Workstation:** run `terraform -chdir=terraform plan`. Expected: 1 to change (the brute-force rule).
3. **Workstation:** run `terraform -chdir=terraform apply` and confirm with `yes`.
4. **Defender:** **Microsoft Sentinel > Configuration > Analytics**, open the rule. The query now starts with `let threshold = 3;`.

To revert, remove the line (the default is 5) and apply again. Variables available for tuning: `bruteforce_threshold`, `bruteforce_window_minutes`, `bruteforce_frequency_minutes`, `webscan_threshold`, `webscan_window_minutes`, `webscan_frequency_minutes`.

## Troubleshooting

| Symptom | Fix |
|---|---|
| A workbook panel shows "The query returned no results" | That source has no data in the selected time range; widen the range. |
| A panel shows a query error | Copy the error text. Usually a table that does not exist yet, which `isfuzzy=true` normally tolerates. |
| No incident after 30 minutes | **Analytics**, open the rule, check it is enabled. Run its query manually in Advanced hunting with `ago(60m)` to see whether the events are there. Check `NginxAccess_CL` and `WebAppAudit_CL` contain the burst. |
| Okta `getschema` returns fewer than 4 rows | The connector uses different column names. Send the full `getschema` output so the Okta branch of the rule can be adjusted. |