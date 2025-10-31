# ----------------------------
# NAT Gateway to use unique public IP for outbound traffic, that can be whitelisted on the package repository
# ----------------------------
resource "azurerm_nat_gateway" "nat" {
  name                = "${var.resource_name_prefix}-NatGateway"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
  sku_name            = "Standard"

}

# ----------------------------
# Associate NAT Gateway with Subnet
# ----------------------------
resource "azurerm_subnet_nat_gateway_association" "nat_subnet_assoc" {
  subnet_id      = azurerm_subnet.external.id
  nat_gateway_id = azurerm_nat_gateway.nat.id
}

# ----------------------------
# Associate NAT Gateway with the public ip
# ----------------------------
resource "azurerm_nat_gateway_public_ip_association" "nat_ip_assoc" {
  nat_gateway_id       = azurerm_nat_gateway.nat.id
  public_ip_address_id = azurerm_public_ip.nat_ip.id
}

# ----------------------------
# Public IP used by the NAT Gateway
# ----------------------------
resource "azurerm_public_ip" "nat_ip" {
  name                = "${var.resource_name_prefix}-GatewayPublicIp"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# ---------------------------
# Application Gateway to access the webui
# ---------------------------
resource "azurerm_application_gateway" "app_gateway" {
  name                = "${var.resource_name_prefix}-gateway"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 2
  }

  ssl_certificate {
    name = "${var.resource_name_prefix}-cert"
    data = filebase64(var.ssl_certificate_path)
  }

  gateway_ip_configuration {
    name      = "${var.resource_name_prefix}-gateway-ip"
    subnet_id = azurerm_subnet.gateway.id
  }

  frontend_ip_configuration {
    name                 = "${var.resource_name_prefix}-frontend-ip"
    public_ip_address_id = azurerm_public_ip.gateway_ip.id
  }

  frontend_port {
    name = "${var.resource_name_prefix}-port-443"
    port = 443
  }

  backend_address_pool {
    name = "${var.resource_name_prefix}-backend-pool-lb"
    ip_addresses = [
      local.neteye_cluster_ip
    ]
  }

  backend_http_settings {
    name                  = "${var.resource_name_prefix}-http-settings"
    cookie_based_affinity = "Disabled"
    port                  = 443
    protocol              = "Https"
    request_timeout       = 60
  }

  http_listener {
    name                           = "${var.resource_name_prefix}-listener-http"
    frontend_ip_configuration_name = "${var.resource_name_prefix}-frontend-ip"
    frontend_port_name             = "${var.resource_name_prefix}-port-443"
    protocol                       = "Https"
    ssl_certificate_name           = "${var.resource_name_prefix}-cert"
  }

  request_routing_rule {
    name                       = "${var.resource_name_prefix}-rule1"
    priority                   = 100
    rule_type                  = "Basic"
    http_listener_name         = "${var.resource_name_prefix}-listener-http"
    backend_address_pool_name  = "${var.resource_name_prefix}-backend-pool-lb"
    backend_http_settings_name = "${var.resource_name_prefix}-http-settings"
  }
}

resource "azurerm_subnet" "gateway" {
  name                 = "${var.resource_name_prefix}-gateway-subnet"
  resource_group_name  = data.azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.network.name
  address_prefixes     = [local.application_gateway_prefix]
}

# ---------------------------
# Dedicated subnet for the application gateway
# ---------------------------
resource "azurerm_subnet_network_security_group_association" "gateway" {
  subnet_id                 = azurerm_subnet.gateway.id
  network_security_group_id = azurerm_network_security_group.external.id
}

# ---------------------------
# Public IP of the application gateway
# ---------------------------
resource "azurerm_public_ip" "gateway_ip" {
  name                = "${var.resource_name_prefix}-GatewayIP"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
  allocation_method   = "Static"
}

# ---------------------------
# Application gateway requires to allow inbound traffic on ports 65200 - 65535 of subnet
# ---------------------------
resource "azurerm_network_security_rule" "gateway" {
  name                        = "${var.resource_name_prefix}-gateway"
  priority                    = 300
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_ranges     = ["65200-65535"]
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = data.azurerm_resource_group.rg.name
  network_security_group_name = azurerm_network_security_group.external.name
}