terraform {
  required_version = "~>1.12"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>4.32"
    }
    ansible = {
      source  = "ansible/ansible"
      version = "~>1.3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~>3.7"
    }
  }
}

provider "azurerm" {
  resource_provider_registrations = "none"
  features {}

  client_id       = var.azure_client_id
  client_secret   = var.azure_client_secret
  tenant_id       = var.azure_tenant_id
  subscription_id = var.azure_subscription_id
}

