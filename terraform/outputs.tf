output "resource_group_name" {
  description = "Resource group for the SIEM and the client VMs."
  value       = azurerm_resource_group.siem.name
}

output "workspace_name" {
  description = "Log Analytics workspace with Sentinel enabled."
  value       = azurerm_log_analytics_workspace.law.name
}

output "data_collection_endpoint" {
  description = "DCE to select when associating VMs with the custom-log DCR."
  value       = azurerm_monitor_data_collection_endpoint.dce.name
}

output "data_collection_rules" {
  description = "DCRs to associate with each VM in the portal."
  value = {
    linux_syslog     = azurerm_monitor_data_collection_rule.linux_syslog.name
    linux_customlogs = azurerm_monitor_data_collection_rule.linux_customlogs.name
    windows          = azurerm_monitor_data_collection_rule.windows.name
  }
}
