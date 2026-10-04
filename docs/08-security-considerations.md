# 08 · Security considerations

A logging platform holds sensitive data and is a target in its own right: an attacker who can stop, alter or read the logs can hide their activity. This section covers how the pipeline, the code and the data are protected, and which limitations were accepted for this environment.

## Identity and access

| Control | Implementation |
|---|---|
| No shared workspace keys | Azure Monitor Agent authenticates with each VM's system-assigned managed identity. |
| Least-privilege SaaS access | The Okta API token belongs to a dedicated Read-Only Administrator account and is stored by the Sentinel connector. |
| Access to logs and incidents | Microsoft Sentinel RBAC roles (Reader, Responder, Contributor) assigned per person; the workspace inherits Azure RBAC. |
| Administrative access to VMs | SSH keys only on Linux (no password authentication). SSH and RDP allowed only from the administrator's IP by the network security group. |
| Windows configuration | Applied through Azure Run command via the VM agent, so no extra management ports are opened. |

## Network

- The web server accepts HTTP from the internet by design; it is the public log source.
- The application container is published on `127.0.0.1` only and reached through Nginx. Docker's port publishing bypasses the host firewall, so binding to localhost is what keeps the app port private.
- `ufw` on web-01 allows only SSH and HTTP as a second layer behind the network security group.
- Log ingestion uses TLS to Azure Monitor endpoints.

## Application and container hardening

- Container runs as a non-root user (UID 10001) with a read-only root filesystem, all Linux capabilities dropped, and `no-new-privileges`.
- Application secrets are generated on the host at setup (`openssl rand`), stored root-only in `/opt/siem/.env` (mode 600) and injected as environment variables.
- Passwords are hashed in memory; unknown usernames are checked against a dummy hash so response timing does not reveal valid accounts.
- Audit records are JSON-encoded, which neutralises log injection. Passwords and secrets are never logged.
- Nginx hides its version and sends security headers (`X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`, `Content-Security-Policy`).

## Secrets and repository hygiene

| Control | Implementation |
|---|---|
| Nothing secret in Git | `.gitignore` (committed first) excludes Terraform state and variable files, keys, certificates, `.env` files and virtual environments. Only `terraform.tfvars.example` with placeholders is committed. |
| Subscription ID kept out of code | Supplied through the `ARM_SUBSCRIPTION_ID` environment variable. |
| Secret scanning | `gitleaks` scans both commit history and staged changes before every push (`scripts/pre-push-checks.ps1`). |
| IaC scanning | `checkov` runs before every push. Its built-in policies do not currently cover Log Analytics, data collection rule or Sentinel resources, so it reports no applicable checks; these resources were reviewed manually against the controls in this document. Checkov will apply automatically as VMs or storage are added as code. |
| Reproducible builds | Provider versions are constrained and `.terraform.lock.hcl` is committed. |
| Credential handling | Git uses Git Credential Manager (Windows Credential Manager); no credentials in remote URLs or scripts. Repository credentials are never placed on the VMs; files are copied over SSH. |
| Line endings | `.gitattributes` forces LF for shell scripts so files edited on Windows run on Linux. |
| If a secret were committed | Rotate it immediately; removing it from the latest commit does not remove it from history. |

## Integrity and availability of logs

- Windows Event ID 1102 (audit log cleared) is collected, so tampering with the local Security log is visible.
- Logs are copied off the hosts within minutes, so deleting local files does not remove the central copy.
- Log rotation is configured for both collected files so disks do not fill and stop logging.
- The workbook's ingestion health panel flags any source silent longer than expected (60 minutes for continuous sources, 24 hours for Azure Activity, Entra ID and Okta).
- Daily cap and budget alerts protect against cost-driven outages and runaway spend.

## Privacy

Logs contain personal information: usernames, IP addresses and sign-in locations. Under the New Zealand Privacy Act 2020 this data should be collected for a clear purpose (security monitoring), kept no longer than needed (per-table retention in `07-retention.md`), and accessible only to those who need it (Sentinel RBAC). Screenshots in this repository have personal IP addresses obscured.

## Accepted limitations in this environment

| Limitation | Production approach |
|---|---|
| Web server uses HTTP | TLS with a managed certificate (for example Azure Application Gateway or Let's Encrypt). |
| SSH and RDP reachable from one public IP | Azure Bastion or just-in-time VM access; no public management ports. |
| Terraform state stored locally | Remote backend in Azure Storage with RBAC, versioning and state locking. |
| VMs created in the portal | VMs defined in Terraform; agents and DCRs assigned by Azure Policy. |
| No CSRF tokens or account lockout in the Staff Portal | Add CSRF protection and progressive lockout; lockout was omitted so brute-force activity remains visible to detection. |
| Public ingestion endpoints | Azure Monitor Private Link Scope. |
