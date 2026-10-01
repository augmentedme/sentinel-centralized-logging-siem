data "azurerm_subscription" "current" {}

resource "azurerm_resource_group" "siem" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# The workspace is the log store. Sentinel is a layer on top of it.
resource "azurerm_log_analytics_workspace" "law" {
  name                = var.workspace_name
  location            = azurerm_resource_group.siem.location
  resource_group_name = azurerm_resource_group.siem.name
  sku                 = "PerGB2018"
  retention_in_days   = var.workspace_retention_days
  daily_quota_gb      = var.daily_cap_gb
  tags                = var.tags
}

# Enables Microsoft Sentinel on the workspace.
resource "azurerm_sentinel_log_analytics_workspace_onboarding" "sentinel" {
  workspace_id = azurerm_log_analytics_workspace.law.id
}
