# 04 · Onboard the Linux log sources (web-01)

One Ubuntu VM provides four of the eight required sources:

| Source | Produced by | File or facility | Table |
|---|---|---|---|
| Web server | Nginx | `/var/log/nginx/access.json` | `NginxAccess_CL` |
| Web application | Staff Portal (Flask) audit log | `/var/log/webapp/audit.log` | `WebAppAudit_CL` |
| Container | Staff Portal container stdout/stderr | syslog facility `local0` | `Syslog` |
| Linux system | sshd, sudo, services | syslog `auth`, `authpriv`, `daemon`, `syslog` | `Syslog` |

```
Internet --80--> Nginx (host) --127.0.0.1:8000--> Staff Portal container
                   |                                  |            |
             access.json                         audit.log   stdout -> syslog local0
                   \__________________ Azure Monitor Agent ______________/
                                              |
                                   dcr-linux-customlogs / dcr-linux-syslog
                                              |
                                     law-siem (Sentinel)
```

Each step says **where** to run it:

- **Workstation**: VS Code terminal on your Windows machine, at the repo root.
- **Portal**: portal.azure.com in a browser.
- **web-01**: an SSH session to the VM.

## Step 1: Create the VM (Portal)

**Virtual machines > Create > Azure virtual machine**

**Basics tab**

| Setting | Value |
|---|---|
| Resource group | `rg-siem-demo` |
| Virtual machine name | `web-01` |
| Region | (Asia Pacific) Australia East |
| Availability options | No infrastructure redundancy required |
| Security type | Trusted launch virtual machines (default) |
| Image | Ubuntu Server 24.04 LTS - x64 Gen2 |
| VM architecture | x64 (Arm64 sizes and images differ; everything here is tested on x64) |
| Size | Standard_B2ls_v2 (2 vCPU, 4 GiB). If unavailable in your region, any 2 vCPU / 4 GiB size such as Standard_B2s. |
| Authentication type | SSH public key |
| Username | `azureuser` |
| SSH public key source | Use existing public key |
| SSH public key | Contents of your `.pub` file (see below) |
| Public inbound ports | Allow selected ports: SSH (22), HTTP (80) |

To copy your public key (**Workstation**):

```powershell
Get-Content $HOME\.ssh\id_ed25519.pub | Set-Clipboard
```

Paste it into the SSH public key box. Only the `.pub` file is ever shared.

**Disks tab**: OS disk type Standard SSD. Leave encryption at the default (platform-managed keys). Everything else as default.

**Networking tab**: accept the new virtual network, subnet and public IP. Tick **Delete public IP and NIC when VM is deleted**.

**Management tab**: tick **Enable system assigned managed identity** (the agent authenticates with it). Set **Auto-shutdown** to **Off** so logs are collected continuously.

**Monitoring tab**: leave defaults.

**Advanced tab**: leave defaults.

**Tags tab**: Select `project = centralized-logging-siem`, and `environment = demo`.

**Review + create > Create.** When it finishes, open the VM and note its **Public IP address**.

## Step 2: Restrict SSH to your IP (Portal)

1. Open **web-01 > Networking > Network settings**.
2. Click the inbound rule for port 22 (SSH).
3. Set **Source** to *IP Addresses* and **Source IP addresses** to your public IP followed by `/32` (for example `203.0.113.25/32`).
4. Save. Leave the HTTP (80) rule open to Any: it is a public web server.

If your home IP changes, SSH will stop working until you update this rule.

## Step 3: Connect to the VM (Workstation)

```powershell
ssh azureuser@<public-ip>
```

Type `yes` when asked to confirm the host fingerprint. Your key in `~/.ssh/id_ed25519` is used automatically. The prompt changes to `azureuser@web-01:~$`. Type `exit` to return to your workstation.

## Step 4: Copy the client files to the VM (Workstation)

From the repo root:

```powershell
ssh azureuser@<public-ip> "mkdir -p ~/siem"
scp -r app clients simulator azureuser@<public-ip>:~/siem/
```

Git credentials are deliberately not placed on the VM; files are copied over SSH instead.

## Step 5: Run the setup script (web-01)

```powershell
ssh azureuser@<public-ip>
```

Then, on web-01:

```bash
sudo bash ~/siem/clients/linux/setup-web01.sh
```

It takes 3 to 6 minutes and ends with `Setup complete.` It installs Nginx, Docker, rsyslog and ufw, generates the app secrets in `/opt/siem/.env` (root-only), starts the container, configures Nginx, log rotation and the host firewall, and installs the simulator cron job.

Store the generated passwords in your password manager:

```bash
sudo cat /opt/siem/.env
```

### Check it works (web-01)

```bash
curl -s http://127.0.0.1/health          # ok
sudo docker ps                            # webapp container "Up ... (healthy)"
sudo tail -n 3 /var/log/nginx/access.json # JSON lines
sudo siem-sim                             # run one simulator cycle now
sudo tail -n 3 /var/log/webapp/audit.log  # JSON audit events
sudo grep docker-webapp /var/log/syslog | tail -n 3   # container output via syslog
```

From your browser, open `http://<public-ip>` and sign in as `staff` with the password from `.env`.

## Step 6: Connect the VM to Sentinel (Portal)

1. Search **Data collection rules** and open `dcr-linux-syslog`.
2. **Configuration > Resources > + Add**, select `web-01`, **Apply**. This installs the Azure Monitor Agent on the VM.
3. Open `dcr-linux-customlogs`, **Configuration > Resources > + Add**, select `web-01`, **Apply**.
4. Still in `dcr-linux-customlogs > Resources`, tick **Show data collection endpoint column** > Click **"Edit Data Collection Endpoint"** and select `dce-siem` for `web-01`. Save.

Confirm the agent (**web-01**):

```bash
systemctl status azuremonitoragent --no-pager
```

It should show `active (running)`. Allow 10 to 20 minutes for the first data.

## Step 7: Verify in Sentinel (Defender portal)

**security.microsoft.com > Investigation & response > Hunting > Advanced hunting.** Paste each query into the query editor and click **Run query**.
Save each one for reuse: **Save > Save as**, then:

- **Name:** as in the comment on the first line of the query (for example `Web server - NginxAccess_CL`).
- **Location:** for the first query, select **Shared queries > New folder** and name the folder `Source validation`. For the following queries, select the existing `Source validation` folder.
- Click **Save**.

```kusto
// Web server - NginxAccess_CL
NginxAccess_CL
| extend e = parse_json(RawData)
| project TimeGenerated, SourceIP = tostring(e.remote_addr), Method = tostring(e.request_method),
          Uri = tostring(e.request_uri), Status = toint(e.status), UserAgent = tostring(e.http_user_agent)
| order by TimeGenerated desc
| take 20
```

```kusto
// Web application - WebAppAudit_CL
WebAppAudit_CL
| extend e = parse_json(RawData)
| project TimeGenerated, Event = tostring(e.event), Outcome = tostring(e.outcome),
          User = tostring(e.user), SourceIP = tostring(e.src_ip), Path = tostring(e.path)
| order by TimeGenerated desc
| take 20
```

```kusto
// Container - Syslog local0
Syslog
| where Facility == "local0"
| project TimeGenerated, Computer, ProcessName, SeverityLevel, SyslogMessage
| order by TimeGenerated desc
| take 20
```

```kusto
// Linux system - Syslog auth
Syslog
| where Facility in ("auth", "authpriv")
| project TimeGenerated, Computer, ProcessName, SyslogMessage
| order by TimeGenerated desc
| take 20
```

## Simulated activity

`/etc/cron.d/siem-sim` runs `siem-sim` every 10 minutes: normal browsing, occasional staff sign-ins (including a denied admin page visit), a few failed logins, occasional path scans and invalid-user SSH attempts. Normal cycles stay below alert thresholds. To trigger the alerts on demand:

- **web-01:** `sudo siem-sim burst`
- **Workstation** (external source IP): `.\simulator\attack-burst.ps1 -Target <public-ip>`

## Security notes

- The container runs as a non-root user with a read-only filesystem, all Linux capabilities dropped and `no-new-privileges`.
- The app port is published on `127.0.0.1` only; Docker's port publishing bypasses ufw, so binding to localhost is what keeps it private.
- Secrets are generated on the host, stored root-only in `/opt/siem/.env`, injected as environment variables, and never committed.
- Passwords are hashed in memory, unknown usernames get a dummy hash check (no timing-based user enumeration), and audit records are JSON-encoded (no log injection). Passwords are never logged.
- SSH is key-only and limited to the administrator's IP by the NSG; ufw adds a host-level layer.
- Known demo limitations, listed as improvements: HTTP only (production would use TLS with a managed certificate), no CSRF tokens, and no account lockout (left out so brute-force attempts stay visible for detection).

## Troubleshooting

| Symptom | Fix |
|---|---|
| `ssh: connect ... timed out` | Your public IP changed or the NSG rule is wrong. Update the SSH rule source (Step 2). |
| `$'\r': command not found` | Windows line endings. Run `sed -i 's/\r$//' ~/siem/clients/linux/setup-web01.sh` and re-run. |
| VM size greyed out as "Size not available" | Capacity or subscription restriction in that region. Pick another 2 vCPU / 4 GiB size (B2ls_v2, B2s). |
| Deployment fails with a quota error | Check **Subscriptions > Usage + quotas** for that VM family, or choose a size from a family with available quota. |
| `docker-compose-v2` not found | Run `sudo apt-get update` and retry; make sure the image is Ubuntu 24.04. |
| Container not healthy | `sudo docker logs webapp` usually shows a missing variable in `/opt/siem/.env`. |
| No rows in `NginxAccess_CL` or `WebAppAudit_CL` after 20 minutes | Check the DCE was selected for web-01 on `dcr-linux-customlogs` (Step 6.4) and the files have new lines (`sudo tail -f /var/log/nginx/access.json`). |
| No rows in `Syslog` | `systemctl status azuremonitoragent`; confirm web-01 is listed under `dcr-linux-syslog > Resources`. |