terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
  }

  # State is kept locally and git-ignored for this demo.
  # Production: use a remote backend (Azure Storage with RBAC,
  # versioning and soft delete) so state is shared, locked and backed up.
}

# Subscription is read from the ARM_SUBSCRIPTION_ID environment variable,
# so no subscription ID is ever written into the repository.
provider "azurerm" {
  features {}
}

provider "azapi" {}
