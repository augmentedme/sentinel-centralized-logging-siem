# ---------------------------------------------------------------------
# Data Collection Endpoint: ingestion URL used for custom log files.
# ---------------------------------------------------------------------
resource "azurerm_monitor_data_collection_endpoint" "dce" {
  name                = "dce-siem"
  location            = azurerm_resource_group.siem.location
  resource_group_name = azurerm_resource_group.siem.name
  kind                = "Linux"
  tags                = var.tags
}

# ---------------------------------------------------------------------
# DCR 1: Linux syslog. Covers:
#   auth, authpriv  -> SSH, sudo, login activity (Linux system logs)
#   daemon, syslog  -> service and system messages
#   local0          -> Docker container stdout/stderr (syslog log driver)
# ---------------------------------------------------------------------
resource "azurerm_monitor_data_collection_rule" "linux_syslog" {
  name                = "dcr-linux-syslog"
  location            = azurerm_resource_group.siem.location
  resource_group_name = azurerm_resource_group.siem.name
  kind                = "Linux"
  description         = "Linux system logs and container output via syslog."
  tags                = var.tags

  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.law.id
      name                  = "law-destination"
    }
  }

  data_sources {
    syslog {
      name           = "syslog-system-and-containers"
      streams        = ["Microsoft-Syslog"]
      facility_names = ["auth", "authpriv", "daemon", "syslog", "local0"]
      log_levels     = ["Info", "Notice", "Warning", "Error", "Critical", "Alert", "Emergency"]
    }
  }

  data_flow {
    streams      = ["Microsoft-Syslog"]
    destinations = ["law-destination"]
  }

  depends_on = [azurerm_sentinel_log_analytics_workspace_onboarding.sentinel]
}

# ---------------------------------------------------------------------
# DCR 2: Linux custom log files (Nginx access log, web app audit log).
# Both files contain one JSON object per line.
# ---------------------------------------------------------------------
locals {
  custom_log_sources = {
    NginxAccess_CL = {
      source_name = "nginx-access-log"
      path        = "/var/log/nginx/access.json"
    }
    WebAppAudit_CL = {
      source_name = "webapp-audit-log"
      path        = "/var/log/webapp/audit.log"
    }
  }
}

resource "azurerm_monitor_data_collection_rule" "linux_customlogs" {
  name                        = "dcr-linux-customlogs"
  location                    = azurerm_resource_group.siem.location
  resource_group_name         = azurerm_resource_group.siem.name
  kind                        = "Linux"
  description                 = "Nginx access log and web application audit log."
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.dce.id
  tags                        = var.tags

  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.law.id
      name                  = "law-destination"
    }
  }

  dynamic "stream_declaration" {
    for_each = local.custom_log_sources
    content {
      stream_name = "Custom-${stream_declaration.key}"
      column {
        name = "TimeGenerated"
        type = "datetime"
      }
      column {
        name = "RawData"
        type = "string"
      }
      column {
        name = "FilePath"
        type = "string"
      }
      column {
        name = "Computer"
        type = "string"
      }
    }
  }

  data_sources {
    dynamic "log_file" {
      for_each = local.custom_log_sources
      content {
        name          = log_file.value.source_name
        format        = "text"
        streams       = ["Custom-${log_file.key}"]
        file_patterns = [log_file.value.path]
      }
    }
  }

  dynamic "data_flow" {
    for_each = local.custom_log_sources
    content {
      streams       = ["Custom-${data_flow.key}"]
      destinations  = ["law-destination"]
      output_stream = "Custom-${data_flow.key}"
      transform_kql = "source"
    }
  }

  depends_on = [azapi_resource.custom_table]
}

# ---------------------------------------------------------------------
# DCR 3: Windows. Security events are filtered with XPath to the IDs
# that matter for detection (keeps cost down), plus System channel
# errors and warnings.
# ---------------------------------------------------------------------
locals {
  windows_security_event_ids = [
    1102, # audit log cleared
    4624, # successful logon
    4625, # failed logon
    4634, # logoff
    4648, # logon with explicit credentials
    4672, # special (admin) privileges assigned
    4688, # process created
    4720, # user account created
    4722, # user account enabled
    4724, # password reset attempt
    4725, # user account disabled
    4726, # user account deleted
    4728, # member added to global security group
    4732, # member added to local security group
    4740, # account locked out
    4756, # member added to universal security group
  ]
  windows_security_xpath = "Security!*[System[(${join(" or ", [for id in local.windows_security_event_ids : "EventID=${id}"])})]]"
}

resource "azurerm_monitor_data_collection_rule" "windows" {
  name                = "dcr-windows-security"
  location            = azurerm_resource_group.siem.location
  resource_group_name = azurerm_resource_group.siem.name
  kind                = "Windows"
  description         = "Windows security events and System log errors and warnings."
  tags                = var.tags

  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.law.id
      name                  = "law-destination"
    }
  }

  data_sources {
    windows_event_log {
      name           = "security-events"
      streams        = ["Microsoft-SecurityEvent"]
      x_path_queries = [local.windows_security_xpath]
    }
    windows_event_log {
      name           = "system-events"
      streams        = ["Microsoft-Event"]
      x_path_queries = ["System!*[System[(Level=1 or Level=2 or Level=3)]]"]
    }
  }

  data_flow {
    streams      = ["Microsoft-SecurityEvent"]
    destinations = ["law-destination"]
  }

  data_flow {
    streams      = ["Microsoft-Event"]
    destinations = ["law-destination"]
  }

  depends_on = [azurerm_sentinel_log_analytics_workspace_onboarding.sentinel]
}

# ---------------------------------------------------------------------
# Cloud provider: Azure subscription Activity Log -> AzureActivity table.
# ---------------------------------------------------------------------
resource "azurerm_monitor_diagnostic_setting" "activity_log" {
  name                       = "activity-log-to-sentinel"
  target_resource_id         = data.azurerm_subscription.current.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

  enabled_log { category = "Administrative" }
  enabled_log { category = "Security" }
  enabled_log { category = "Policy" }
  enabled_log { category = "Alert" }
  enabled_log { category = "ServiceHealth" }
  enabled_log { category = "ResourceHealth" }
}
