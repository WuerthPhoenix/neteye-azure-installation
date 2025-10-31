data "azurerm_resource_group" "rg" {
  name = var.resource_group_name
}

resource "random_password" "admin_password" {
  length = 16
  lower  = false
}

locals {
  network_prefix             = "10.1.0.0/24"
  neteye_cluster_ip          = "10.1.0.200"
  bastion_network_prefix     = "10.2.0.0/26"
  application_gateway_prefix = "10.3.0.0/26"
  vm_base_ip_idx             = 4

  vms_configuration = zipmap(
    range(var.cluster_size),
    [for i in range(var.cluster_size) : {
      hostname = format(var.vm_hostname_template, i)
      ip       = cidrhost(local.network_prefix, local.vm_base_ip_idx + i)
      # Cyclically distribute VMs across available zones
      zone = var.azure_availability_zones[i % length(var.azure_availability_zones)]
    }]
  )
}

resource "azurerm_network_security_group" "external" {
  name                = "${var.resource_name_prefix}ExternalSecurityGroup"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
}

resource "azurerm_subnet_network_security_group_association" "external" {
  subnet_id                 = azurerm_subnet.external.id
  network_security_group_id = azurerm_network_security_group.external.id
}

resource "azurerm_virtual_network" "network" {
  name = "${var.resource_name_prefix}Vnet"
  address_space = [
    local.network_prefix,
    local.bastion_network_prefix,
    local.application_gateway_prefix,
  ]
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
}

resource "azurerm_subnet" "external" {
  name                 = "external"
  resource_group_name  = data.azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.network.name
  address_prefixes     = [local.network_prefix]
}
resource "azurerm_network_interface" "external_nic" {
  for_each = local.vms_configuration

  name                  = format("%s%02d-Nic", var.resource_name_prefix, each.key)
  resource_group_name   = data.azurerm_resource_group.rg.name
  location              = data.azurerm_resource_group.rg.location
  ip_forwarding_enabled = true

  ip_configuration {
    name                          = "external-ipconfig${each.key}"
    subnet_id                     = azurerm_subnet.external.id
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.ip
  }
}

resource "azurerm_managed_disk" "data_disk" {
  for_each = local.vms_configuration

  name                 = format("%s%02d-DataDisk", var.resource_name_prefix, each.key)
  location             = data.azurerm_resource_group.rg.location
  resource_group_name  = data.azurerm_resource_group.rg.name
  storage_account_type = "StandardSSD_LRS"
  create_option        = "Empty"
  disk_size_gb         = var.disk_size
  zone                 = each.value.zone
}
resource "azurerm_virtual_machine_data_disk_attachment" "data_disk_attachment" {
  for_each = local.vms_configuration

  managed_disk_id    = azurerm_managed_disk.data_disk[each.key].id
  virtual_machine_id = azurerm_linux_virtual_machine.vm[each.key].id
  lun                = 0
  caching            = "ReadOnly"
}

resource "azurerm_linux_virtual_machine" "vm" {
  for_each = local.vms_configuration

  name                = format("%s%02d-Vm", var.resource_name_prefix, each.key)
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
  size                = var.vm_size

  computer_name                   = each.value.hostname
  admin_username                  = "ne_root"
  admin_password                  = random_password.admin_password.result
  disable_password_authentication = false
  zone                            = each.value.zone

  source_image_reference {
    publisher = "redhat"
    offer     = "rhel-byos"
    sku       = "rhel-lvm810-gen2"
    version   = "latest"
  }
  plan {
    name      = "rhel-lvm810-gen2"
    product   = "rhel-byos"
    publisher = "redhat"
  }
  license_type = "RHEL_BYOS"

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  network_interface_ids = [azurerm_network_interface.external_nic[each.key].id]

}

# ---------------------------
# Generate an example of /etc/hosts file
# ---------------------------
resource "local_file" "hosts_file" {
  filename = "${path.module}/hosts.txt"

  content = join("\n", concat(flatten([
    for key, vm in local.vms_configuration : [
      "${vm.ip} ${format("neteye%02d.neteyelocal", key)}",
      "${vm.ip} ${vm.hostname}\n"
    ]
    ]
    )),
    [
      "# NetEye Cluster IP",
      "${local.neteye_cluster_ip} neteye.neteyelocal\n"
    ]
  )
}