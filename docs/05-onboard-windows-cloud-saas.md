# 05 · Onboard Windows, cloud, directory and SaaS sources

| Source | Produced by | Collection | Table |
|---|---|---|---|
| Windows system logs | `win-01` (Windows Server 2025) | Azure Monitor Agent, `dcr-windows-security` | `SecurityEvent`, `Event` |
| Cloud provider | Azure subscription Activity Log | Diagnostic setting (Terraform) | `AzureActivity` |
| Directory service | Microsoft Entra ID | Sentinel Entra ID connector | `SigninLogs`, `AuditLogs` |
| SaaS application | Okta System Log API | Sentinel Okta connector (API polling) | `OktaV2_CL` |

Each step says **where** to run it: **Workstation** (VS Code terminal on your Windows machine, repo root), **Portal** (portal.azure.com), **Defender** (security.microsoft.com), **Entra** (entra.microsoft.com) or **Okta** (your Okta admin console).

---

## Part A: Windows (win-01)

### Step A1: Create the VM (Portal)

**Virtual machines > Create > Azure virtual machine**

**Basics tab**

| Setting | Value |
|---|---|
| Resource group | `rg-siem-demo` |
| Virtual machine name | `win-01` |
| Region | (Asia Pacific) Australia East |
| Availability options | No infrastructure redundancy required |
| Security type | Trusted launch virtual machines (default) |
| Image | Windows Server 2025 Datacenter: Azure Edition - x64 Gen2 |
| Size | Standard_B2ls_v2 (2 vCPU, 4 GiB). If unavailable in your region, any 2 vCPU / 4 GiB size such as Standard_B2s. |
| Username | `siemadmin` (not `admin` or `administrator`) |
| Password | Long random password, saved in your password manager first |
| Public inbound ports | Allow selected ports: RDP (3389) |
| Licensing | Leave the existing-license (Hybrid Benefit) box unticked |

**Disks tab**: Choose Standard SSD. Leave everything else as default.

**Networking tab**: select the **existing** virtual network created with web-01. Select default subnet. Tick **Delete public IP and NIC when VM is deleted**.

**Management tab**: tick **Enable system assigned managed identity**. **Auto-shutdown: Off**.

**Monitoring tab**: leave defaults.

**Advanced tab**: leave defaults.

**Tags tab**: `project = centralized-logging-siem`, `environment = demo`. 

**Review + create > Create.** When it finishes, open the VM and note its **Public IP address**.

If creation fails with a **quota** error, check **Subscriptions > Usage + quotas** for "Total Regional vCPUs" and the B-series family quotas ("Standard BSv2 Family vCPUs" for B2ls_v2, "Standard BS Family vCPUs" for B2s) in Australia East. web-01 and win-01 need 4 vCPUs together.

### Step A2: Restrict RDP to your IP (Portal)

**win-01 > Networking > Network settings**, open the RDP (3389) rule, set **Source** to *IP Addresses* with your public IP and `/32`. Save.

### Step A3: Configure Windows with Run command (Portal)

Run command executes a script through the Azure VM agent, so no RDP session or file copy is needed.

1. In VS Code (**Workstation**), open `clients/windows/setup-win01.ps1`, press **Ctrl+A**, **Ctrl+C**.
2. In the portal: **win-01 > Operations > Run command > RunPowerShellScript**.
3. Paste the script into the box and click **Run**. It takes 1 to 3 minutes.
4. The output should end with:

```
==> Running the simulator once now
  Failed logon events (4625) in the last 5 minutes: <a number above 0>

Setup complete.
```

### Step A4: Connect win-01 to Sentinel (Portal)

1. Search **Data collection rules**, open `dcr-windows-security`.
2. **Configuration > Resources > + Add**, select `win-01`, **Apply**. This installs the Azure Monitor Agent.

Allow 10 to 20 minutes for the first events.

### Step A5 (optional): Look at the VM over RDP (Workstation)

```powershell
mstsc /v:<win-01-public-ip>
```

Sign in as `siemadmin`. **Event Viewer > Windows Logs > Security** shows the 4625 events. Not required for the build, but useful for confirming events locally on the host.

---

## Part B: Cloud provider (Azure Activity Log)

Already configured by Terraform (`activity-log-to-sentinel`). Every portal action you have taken (creating VMs, rules, tags) is already in `AzureActivity`. Nothing to do except verify (Part E).

---

## Part C: Directory service (Microsoft Entra ID)

### Step C1: Confirm the P2 (or P1) licence (Entra)

**entra.microsoft.com > Billing > Licenses > All products.** Microsoft Entra ID P2 (trial) should be listed. Sign-in logs cannot be exported without P1 or P2.

### Step C2: Install and connect the connector (Defender)

Sentinel configuration pages have moved from the Azure portal to the Defender portal. Use **security.microsoft.com**, not portal.azure.com.

1. In the left menu, expand **Microsoft Sentinel > Content management** and select **Content hub**.
2. Search `Microsoft Entra ID`, select the **Microsoft Entra ID** solution and click **Install**. Wait for **Installed**.
3. In the left menu, expand **Microsoft Sentinel > Configuration** and select **Data connectors**.
4. Search `Microsoft Entra ID`, select it and click **Open connector page** from the three dots on the right side. You may need to wait a few minutes for Entra ID to appear in the connector list.
5. Under **Configuration** at the bottom of the page, tick **Sign-In Logs** and **Audit Logs**, then click **Apply Changes**.

The connector status changes to **Connected** within about 30 minutes. This requires the Global Administrator or Security Administrator role, which the subscription owner has.

### Step C3: Generate sign-in activity (browser)

1. Open a **private/incognito** browser window and go to `https://myapps.microsoft.com`.
2. Sign in as `alice@<your-tenant>.onmicrosoft.com` with a **wrong** password 4 times.
3. Then sign in with the correct password. If asked to register MFA, you can complete it with the Microsoft Authenticator app, or choose "Skip for now" if offered.
4. Repeat with `bob` once a day so history builds up.

Entra sign-in logs arrive in Sentinel after roughly 5 to 15 minutes.

---

## Part D: SaaS application (Okta)

### Step D1: Check the API token is least-privilege (Okta)

The Okta API token has the same permissions as the user who created it. It should be created by a dedicated **Read-Only Administrator** account (for example `svc-sentinel`), not your own super-admin account. If you created it as yourself:

1. **Directory > People > Add person**: create `svc-sentinel`, set a password.
2. **Security > Administrators > Add administrator**: assign `svc-sentinel` the **Read-Only Administrator** role.
3. Sign out, sign in as `svc-sentinel`, then **Security > API > Tokens > Create token** named `sentinel-connector`.
4. Store the token in your password manager, then revoke the old token from your own account.

### Step D2: Install and connect the connector (Defender)

1. **Microsoft Sentinel > Content management > Content hub**, search `Okta`, select **Okta Single Sign-On**, **Install**.
2. **Microsoft Sentinel > Configuration > Data connectors**, search `Okta`. If there are several versions, choose the one that does **not** mention "Azure Functions" (the codeless/polling connector).
3. **Open connector page**. Enter your Okta domain (for example `integrator-1234567.okta.com`, without `https://`) and the API token. Click **Connect**.

4. Confirm the connector page lists `OktaV2_CL` as the destination table.

The token is stored by the Sentinel connector, never in this repository.

### Step D3: Generate Okta activity (browser)

In a private window, sign in to your Okta org as a test user with a **wrong** password 3 to 4 times, then correctly. Repeat daily. Okta events typically arrive within 10 to 20 minutes.

---

## Part E: Verify in Sentinel (Defender)

**Investigation & response > Hunting > Advanced hunting.** Run and save each query in the `Source validation` folder.

```kusto
// Windows: failed logons
SecurityEvent
| where EventID == 4625
| project TimeGenerated, Computer, Account = TargetUserName, LogonType, IpAddress, FailureReason = Status
| order by TimeGenerated desc
| take 20
```

```kusto
// Windows: account and group management
SecurityEvent
| where EventID in (4720, 4722, 4724, 4728, 4732, 4740, 4756)
| project TimeGenerated, Computer, EventID, Activity, TargetUserName, SubjectUserName
| order by TimeGenerated desc
```

```kusto
// Windows: System log errors and warnings
Event
| project TimeGenerated, Computer, Source, EventLevelName, EventID, RenderedDescription
| order by TimeGenerated desc
| take 20
```

```kusto
// Cloud provider: Azure control-plane activity
AzureActivity
| project TimeGenerated, Caller, OperationNameValue, ActivityStatusValue, ResourceGroup, CallerIpAddress
| order by TimeGenerated desc
| take 20
```

```kusto
// Directory: Entra ID sign-ins (ResultType 0 = success, 50126 = wrong password)
SigninLogs
| project TimeGenerated, UserPrincipalName, AppDisplayName, ResultType, ResultDescription, IPAddress, Location
| order by TimeGenerated desc
| take 20
```

```kusto
// Directory: Entra ID audit (user, group and role changes)
AuditLogs
| project TimeGenerated, OperationName, Result, InitiatedBy, TargetResources
| order by TimeGenerated desc
| take 20
```

```kusto
// SaaS: Okta System Log (latest events)
OktaV2_CL
| project TimeGenerated, EventType = EventOriginalType, Result = EventResult,
          User = ActorUsername, SourceIP = SrcIpAddr
| order by TimeGenerated desc
| take 20
```

`take 20` returns only the 20 most recent rows. To see activity across the whole collection period, summarise by day instead (set the time range picker to 7 days if it does not switch automatically):

```kusto
// SaaS: Okta daily activity
OktaV2_CL
| where TimeGenerated > ago(7d)
| summarize Events = count(), Failures = countif(EventResult =~ "Failure") by Day = bin(TimeGenerated, 1d)
| order by Day asc
```

## Simulated and real activity

| Source | How data is generated |
|---|---|
| Windows | Scheduled task every 30 minutes (1 to 3 failed logons with non-existent usernames); test account creation at setup |
| Azure Activity | Every portal, CLI and Terraform action |
| Entra ID | Manual sign-ins as alice and bob (wrong and correct passwords) |
| Okta | Manual sign-ins as the Okta test user |

To trigger Windows failures on demand (for example to test the brute-force alert), run this through **Run command**:

```powershell
& 'C:\ProgramData\SIEM\win-sim.ps1' -Burst
```

## Security notes

- RDP is limited to the administrator's IP. Configuration uses Run command through the Azure VM agent, so no extra management ports are opened.
- The simulator only uses usernames that do not exist, so no real account can be locked out.
- The test account's password is random, never stored and never displayed.
- The Okta token belongs to a read-only service account and is held by the Sentinel connector.
- The Windows DCR collects 16 selected Security event IDs rather than all events, which keeps ingestion cost low while covering logons, privilege use, account and group changes, process creation and log clearing.

## Troubleshooting

| Symptom | Fix |
|---|---|
| VM creation fails with a quota error | Check **Subscriptions > Usage + quotas** in Australia East. If the B-series v2 family is at its limit, choose a size from a family with free quota (for example Standard_B2s). If **Total Regional vCPUs** is at its limit, request a quota increase or free up vCPUs. |
| Run command output shows 0 failed logons | Rerun the script; if still 0, RDP in and run `auditpol /get /subcategory:Logon` to confirm failure auditing is enabled. |
| No rows in `SecurityEvent` after 20 minutes | Confirm win-01 is listed under `dcr-windows-security > Resources`, and the VM has the `AzureMonitorWindowsAgent` extension (**win-01 > Extensions + applications**). |
| `SigninLogs` empty | Confirm the P1/P2 licence (C1), and that Sign-In Logs is ticked on the connector (C2). The first logs can take up to 30 minutes. |
| Okta connector shows an error | Check the domain has no `https://` and the token is valid (Okta **Security > API > Tokens**). |
