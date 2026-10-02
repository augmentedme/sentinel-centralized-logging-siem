# 01 · Architecture

![Architecture](images/architecture.png)

Source: [`images/architecture.svg`](images/architecture.svg)

## Overview

All logs are collected into a single Log Analytics workspace, `law-siem`, with Microsoft Sentinel enabled. Sentinel is operated through the unified Microsoft Defender portal. Each source uses the most native, supported collection method available, so there are no custom forwarders or collector services to maintain.

## Sources and collection

| Requirement | Source | Collection method | Table |
|---|---|---|---|
| Web server | Nginx on `web-01` | Azure Monitor Agent, custom text log DCR (JSON lines) | `NginxAccess_CL` |
| Web application | Staff Portal (Flask) security audit log | Azure Monitor Agent, custom text log DCR (JSON lines) | `WebAppAudit_CL` |
| Container | Staff Portal container stdout/stderr | Docker syslog log driver, facility `local0`, Syslog DCR | `Syslog` |
| Linux system | `web-01` sshd, sudo, services | Syslog DCR (`auth`, `authpriv`, `daemon`, `syslog`) | `Syslog` |
| Windows system | `win-01` | Windows events DCR (16 Security event IDs; System errors and warnings) | `SecurityEvent`, `Event` |
| Cloud provider | Azure subscription Activity Log | Diagnostic setting created by Terraform | `AzureActivity` |
| Directory service | Microsoft Entra ID | Sentinel Entra ID connector | `SigninLogs`, `AuditLogs` |
| SaaS application | Okta System Log API | Sentinel Okta connector (codeless, API polling) | `OktaV2_CL` |

## Design decisions

**Microsoft Sentinel as the SIEM.** A managed service: no cluster to size, patch or scale. It provides native connectors for most of the required sources, KQL for detection and hunting, incident management, and per-table retention tiers. The trade-offs are cost that scales with ingestion volume and dependence on Microsoft. A self-hosted Elastic or Wazuh stack would be the better fit for a client with a tight budget, a strict requirement to keep data on premises, or an existing Elastic team.

**Azure Monitor Agent with Data Collection Rules.** AMA is Microsoft's supported agent. DCRs define what is collected and where it goes, filter at the source to control cost (for example 16 selected Windows Security event IDs instead of all events), and are managed as code.

**JSON log lines stored in `RawData`.** Nginx and the web application both write one JSON object per line. The custom tables store the raw line and queries parse it with `parse_json()`. Ingestion stays simple and new fields never break collection. At larger scale, a DCR transformation would parse the fields into typed columns at ingestion time.

**Audit log separate from container output.** The web application's security audit trail (logins, access denials, admin access) is a deliberate, structured record with its own table and retention. The container's stdout/stderr is operational output (requests, warnings, errors) shipped through Docker's syslog driver. They serve different audiences and are kept separate, as in production systems.

**Built-in connectors for Entra ID and Okta.** Both are maintained by Microsoft, handle authentication, paging and checkpointing, and need no code. The Okta API token belongs to a read-only service account and is stored by the connector, not in this repository.

**One normalised view of authentication failures.** Each source records failed logins differently. The brute-force rule, the workbook and the hunting query map all five into one schema (time, source, account, IP) so they can be counted together. Production would adopt Microsoft's ASIM authentication parsers for the same purpose.

**Everything that defines the SIEM is code.** Terraform manages the workspace, Sentinel, tables, collection rules, retention, analytics rules, workbook and budget. Client configuration is scripted (`setup-web01.sh`, `setup-win01.ps1`). VMs were created in the portal and are listed as an improvement.

## Environment

| Resource | Size | Notes |
|---|---|---|
| `web-01` | Standard_B2s, Ubuntu 24.04 | Nginx, Docker, Staff Portal, simulator |
| `win-01` | Standard_B2ms, Windows Server 2025 | Audit policy, failed-logon simulator |
| `law-siem` | Pay-as-you-go, 2 GB/day cap | Sentinel enabled |
| Region | Australia East | All resources |
