locals {
  cluster_vip_conf = {
    base_port = 61000
    base_ip   = 33
    n_of_vips = 24
  }
  cluster_vips = zipmap(
    range(local.cluster_vip_conf.n_of_vips),
    [for i in range(local.cluster_vip_conf.n_of_vips) : {
      name    = format("Vip%03d", local.cluster_vip_conf.base_ip + i)
      lb_port = local.cluster_vip_conf.base_port + local.cluster_vip_conf.base_ip + i
      ip      = cidrhost(local.network_prefix, local.cluster_vip_conf.base_ip + i)
    }]
  )

  external_fip_probe_port = 61000
  external_fip_accessible_ports = [
    80,
    443,
    514,
    944,
    4222,
    5044,
    5045,
    5665,
    7422,
    8200,
    8220,
    9004,
    9200,
  ]
}

# Internal VIPs
resource "azurerm_lb" "internal_lb" {
  name                = "${var.resource_name_prefix}-InternalLb"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location

  dynamic "frontend_ip_configuration" {
    for_each = local.cluster_vips

    content {
      name                          = frontend_ip_configuration.value.name
      subnet_id                     = azurerm_subnet.external.id
      private_ip_address_allocation = "Static"
      private_ip_address            = frontend_ip_configuration.value.ip
    }
  }
}

resource "azurerm_lb_backend_address_pool" "internal_lb_backend_pool" {
  name            = "${var.resource_name_prefix}-InternalLbBackendPool"
  loadbalancer_id = azurerm_lb.internal_lb.id
}
resource "azurerm_network_interface_backend_address_pool_association" "internal_lb_ass" {
  for_each = local.vms_configuration

  network_interface_id    = azurerm_network_interface.external_nic[each.key].id
  ip_configuration_name   = azurerm_network_interface.external_nic[each.key].ip_configuration[0].name
  backend_address_pool_id = azurerm_lb_backend_address_pool.internal_lb_backend_pool.id
}

resource "azurerm_lb_probe" "vip_health_probes" {
  for_each = local.cluster_vips

  name                = "${var.resource_name_prefix}-${each.value.name}-VipHealthProbe"
  loadbalancer_id     = azurerm_lb.internal_lb.id
  port                = each.value.lb_port
  interval_in_seconds = 5
  # number_of_probes    = 2
}

resource "azurerm_lb_rule" "vip_lb_rule" {
  for_each = local.cluster_vips

  name                           = "${var.resource_name_prefix}-${each.value.name}-VipLbRule"
  loadbalancer_id                = azurerm_lb.internal_lb.id
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.internal_lb_backend_pool.id]
  protocol                       = "All"
  frontend_port                  = 0
  backend_port                   = 0
  frontend_ip_configuration_name = each.value.name
  probe_id                       = azurerm_lb_probe.vip_health_probes[each.key].id
  floating_ip_enabled            = true
}

resource "azurerm_lb" "external_lb" {
  name                = "${var.resource_name_prefix}-ExternalLb"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location

  frontend_ip_configuration {
    name                          = "${var.resource_name_prefix}-lbIpAddress"
    subnet_id                     = azurerm_subnet.external.id
    private_ip_address_allocation = "Static"
    # Load balancer ip address should match the cluster ip otherwise neteye nodes will discard the traffic
    private_ip_address = local.neteye_cluster_ip
  }
}

resource "azurerm_lb_backend_address_pool" "external_lb_backend_pool" {
  name            = "${var.resource_name_prefix}-ClusterBackendPool"
  loadbalancer_id = azurerm_lb.external_lb.id
}
resource "azurerm_network_interface_backend_address_pool_association" "external_lb_ass" {
  for_each = local.vms_configuration

  network_interface_id    = azurerm_network_interface.external_nic[each.key].id
  ip_configuration_name   = azurerm_network_interface.external_nic[each.key].ip_configuration[0].name
  backend_address_pool_id = azurerm_lb_backend_address_pool.external_lb_backend_pool.id
}

resource "azurerm_lb_probe" "external_vip_health_probe" {
  name                = "${var.resource_name_prefix}-ExternalVipProbe"
  loadbalancer_id     = azurerm_lb.external_lb.id
  port                = local.external_fip_probe_port
  interval_in_seconds = 5
}

resource "azurerm_lb_rule" "external_vip_lb_rule" {
  for_each = zipmap(
    local.external_fip_accessible_ports,
    local.external_fip_accessible_ports
  )

  name                           = "${var.resource_name_prefix}-${each.key}-ExternalVipLbRule"
  loadbalancer_id                = azurerm_lb.external_lb.id
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.external_lb_backend_pool.id]
  protocol                       = "Tcp"
  frontend_port                  = each.value
  backend_port                   = each.value
  frontend_ip_configuration_name = azurerm_lb.external_lb.frontend_ip_configuration[0].name
  probe_id                       = azurerm_lb_probe.external_vip_health_probe.id
  floating_ip_enabled            = true
}

resource "azurerm_network_security_rule" "neteye_ports" {
  name                        = "neteye_ports"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_ranges     = local.external_fip_accessible_ports
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = data.azurerm_resource_group.rg.name
  network_security_group_name = azurerm_network_security_group.external.name
}
