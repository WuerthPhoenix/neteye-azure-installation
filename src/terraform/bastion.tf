# ----------------------------
# Dedicated subnet for Azure Bastion
# ----------------------------
resource "azurerm_subnet" "bastion_subnet" {
  # The subnet name must be 'AzureBastionSubnet' to work with Azure Bastion
  name                 = "AzureBastionSubnet"
  resource_group_name  = data.azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.network.name
  address_prefixes     = [local.bastion_network_prefix]
}

# ----------------------------
# Dedicated public ip for Azure Bastion
# ----------------------------
resource "azurerm_public_ip" "bastion_ip" {
  name                = "${var.resource_name_prefix}bastion-ip"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

# ----------------------------
# Azure Bastion Host
# ----------------------------
resource "azurerm_bastion_host" "bastion" {
  name                = "${var.resource_name_prefix}Bastion"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location

  ip_configuration {
    name                 = "${var.resource_name_prefix}ip-configuration"
    subnet_id            = azurerm_subnet.bastion_subnet.id
    public_ip_address_id = azurerm_public_ip.bastion_ip.id
  }
}