# ---------------------------------------------------------------------
# Dashboard: Sentinel workbook "SIEM Security Overview".
# The workbook definition is kept in /workbooks as JSON (the same format
# the portal exports). The workspace ID is injected here so the JSON in
# the repo stays environment-neutral.
# ---------------------------------------------------------------------
resource "azurerm_application_insights_workbook" "security_overview" {
  # Workbook resource names must be GUIDs.
  name                = "5d1f3c2a-8b7e-4c6d-9a0f-2e4b6c8d1a37"
  resource_group_name = azurerm_resource_group.siem.name
  location            = azurerm_resource_group.siem.location
  display_name        = "SIEM Security Overview"
  category            = "sentinel"
  source_id           = lower(azurerm_log_analytics_workspace.law.id)
  tags                = var.tags

  data_json = jsonencode(merge(
    jsondecode(file("${path.module}/../workbooks/security-overview.json")),
    { fallbackResourceIds = [lower(azurerm_log_analytics_workspace.law.id)] }
  ))

  depends_on = [azurerm_sentinel_log_analytics_workspace_onboarding.sentinel]
}
