# ---------------------------------------------------------------------
# Analytics rules (alerts). The KQL lives in /detections so it can be
# reviewed and reused for hunting; thresholds are Terraform variables.
# ---------------------------------------------------------------------
resource "azurerm_sentinel_alert_rule_scheduled" "bruteforce" {
  name                       = "siem-bruteforce-cross-source"
  log_analytics_workspace_id = azurerm_sentinel_log_analytics_workspace_onboarding.sentinel.workspace_id
  display_name               = "Brute-force login attempts across sources"
  description                = "One source IP produced ${var.bruteforce_threshold} or more failed logins within ${var.bruteforce_window_minutes} minutes across the web app, Linux SSH, Windows and Entra ID."
  severity                   = "Medium"
  enabled                    = true

  query = templatefile("${path.module}/../detections/bruteforce-cross-source.kql", {
    threshold      = var.bruteforce_threshold
    window_minutes = var.bruteforce_window_minutes
  })
  query_frequency   = "PT${var.bruteforce_window_minutes}M"
  query_period      = "PT${var.bruteforce_window_minutes}M"
  trigger_operator  = "GreaterThan"
  trigger_threshold = 0

  tactics    = ["CredentialAccess"]
  techniques = ["T1110"]

  entity_mapping {
    entity_type = "IP"
    field_mapping {
      identifier  = "Address"
      column_name = "SourceIP"
    }
  }

  alert_details_override {
    display_name_format = "Brute-force login attempts from {{SourceIP}}"
  }

  event_grouping {
    aggregation_method = "AlertPerResult"
  }
}

resource "azurerm_sentinel_alert_rule_scheduled" "webscan" {
  name                       = "siem-web-vulnerability-scanning"
  log_analytics_workspace_id = azurerm_sentinel_log_analytics_workspace_onboarding.sentinel.workspace_id
  display_name               = "Web vulnerability scanning"
  description                = "One source IP requested ${var.webscan_threshold} or more known-sensitive paths within ${var.webscan_window_minutes} minutes."
  severity                   = "Low"
  enabled                    = true

  query = templatefile("${path.module}/../detections/web-vulnerability-scanning.kql", {
    threshold      = var.webscan_threshold
    window_minutes = var.webscan_window_minutes
  })
  query_frequency   = "PT${var.webscan_window_minutes}M"
  query_period      = "PT${var.webscan_window_minutes}M"
  trigger_operator  = "GreaterThan"
  trigger_threshold = 0

  tactics    = ["Reconnaissance"]
  techniques = ["T1595"]

  entity_mapping {
    entity_type = "IP"
    field_mapping {
      identifier  = "Address"
      column_name = "SourceIP"
    }
  }

  alert_details_override {
    display_name_format = "Web vulnerability scanning from {{SourceIP}}"
  }

  event_grouping {
    aggregation_method = "AlertPerResult"
  }

  depends_on = [azapi_resource.custom_table]
}
