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

  subscription_id = var.azure_subscription_id
}

