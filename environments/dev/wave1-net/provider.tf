terraform {
  required_version = ">= 1.8"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.110"
    }
  }

  backend "azurerm" {
    resource_group_name  = "rg-hlb-dev-001"
    storage_account_name = "<STORAGE_ACCOUNT_NAME>"
    container_name       = "terraform-state"
    key                  = "dev/wave1-net/terraform.tfstate"
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}
