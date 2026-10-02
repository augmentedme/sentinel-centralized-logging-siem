# 09 · Further improvements

Listed in suggested order of value.

## Detection and response

1. **Automated response.** A Logic App playbook triggered by the brute-force incident: notify the on-call channel, add the IP to a block list on the network security group or WAF, and comment on the incident.
2. **Detection-as-code pipeline.** CI that runs `terraform plan`, KQL syntax checks and tests against sample data on every merge request, with approval before apply.
3. **ASIM normalisation.** Replace the in-rule normalisation with Microsoft's ASIM authentication and web session parsers so community detections work across all sources.
4. **More detections.** Successful login after repeated failures, impossible travel across Entra ID and Okta, new local administrator on Windows, audit log cleared (1102), container restarts.
5. **Watchlists and threat intelligence.** Allow-list known scanners and internal IPs; enrich IPs with a threat intelligence feed.
6. **UEBA.** Enable Sentinel User and Entity Behaviour Analytics for baseline-driven anomaly detection.
7. **Account lockout and MFA.** Progressive lockout in the application and MFA for the admin role.

## Platform

1. **VMs as code and policy-driven onboarding.** Define VMs in Terraform; use Azure Policy to deploy the Azure Monitor Agent and associate DCRs automatically for every new machine.
2. **Remote Terraform state.** Azure Storage backend with locking, versioning and RBAC.
3. **Private networking.** Azure Monitor Private Link for ingestion; Azure Bastion or just-in-time access instead of public SSH and RDP.
4. **Ingestion-time parsing.** DCR transformations to turn JSON lines into typed columns and drop unneeded fields before ingestion, lowering cost.
5. **Scale-out collection.** A pair of syslog forwarders for network devices and appliances; Container Insights or a Fluent Bit DaemonSet for Kubernetes workloads.
6. **Additional sources.** AWS CloudTrail and GCP audit logs, Microsoft 365 audit logs, firewall and WAF logs.

## Retention and cost

1. **Tiering verbose data.** Move high-volume, low-value tables to the Basic or Auxiliary plan once no scheduled rule depends on them; keep summarised data in the Analytics tier.
2. **Independent archive.** Data export to an immutable storage account with lifecycle tiers for legal hold and regulatory evidence.
3. **Commitment tiers.** At higher daily volumes, a Sentinel commitment tier lowers the price per GB.

## High availability and resilience

The brief did not require high availability. Sentinel and Log Analytics are managed regional services. For resilience: zone-redundant workspace options where available, a second workspace or data export for disaster recovery, and redundant forwarders for any network-device sources.
