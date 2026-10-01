# ---------------------------------------------------------------------
# Custom tables for file-based logs. Each JSON log line is stored in
# RawData and parsed at query time with parse_json(). This keeps
# ingestion simple and tolerant of new fields.
# ---------------------------------------------------------------------
locals {
  custom_log_columns = [
    { name = "TimeGenerated", type = "datetime" },
    { name = "RawData", type = "string" },
    { name = "FilePath", type = "string" },
    { name = "Computer", type = "string" },
  ]
}

resource "azapi_resource" "custom_table" {
  for_each = var.custom_table_retention

  type      = "Microsoft.OperationalInsights/workspaces/tables@2022-10-01"
  name      = each.key
  parent_id = azurerm_log_analytics_workspace.law.id

  body = {
    properties = {
      plan                 = "Analytics"
      retentionInDays      = each.value.interactive
      totalRetentionInDays = each.value.total
      schema = {
        name    = each.key
        columns = local.custom_log_columns
      }
    }
  }
}

# ---------------------------------------------------------------------
# Retention on built-in tables (hot = interactive, cold = total minus
# interactive). Change the values in variables.tf or terraform.tfvars
# and run 'terraform apply'.
# ---------------------------------------------------------------------
resource "azurerm_log_analytics_workspace_table" "builtin" {
  for_each = var.manage_builtin_table_retention ? var.table_retention : {}

  workspace_id            = azurerm_log_analytics_workspace.law.id
  name                    = each.key
  retention_in_days       = each.value.interactive
  total_retention_in_days = each.value.total

  depends_on = [azurerm_sentinel_log_analytics_workspace_onboarding.sentinel]
}
