data "azurerm_resource_group" "rg" {
  name = var.resource_group_name
}

resource "random_password" "admin_password" {
  length = 16
  lower  = false
}

locals {
  network_prefix = "10.1.0.0/24"
  # NOTE: The first 4 IPs are reserved by Azure
  vm_base_ip_idx    = 4
  fw_allowed_prefix = "82.193.25.251/32"

  vms_configuration = zipmap(
    range(var.cluster_size),
    [for i in range(var.cluster_size) : {
      hostname = format(var.vm_hostname_template, i)
      ip       = cidrhost(local.network_prefix, local.vm_base_ip_idx + i)
    }]
  )
}

resource "azurerm_availability_set" "avail_set" {
  name                = "${var.resource_name_prefix}-AvailSet"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
}

resource "azurerm_network_security_group" "external" {
  name                = "${var.resource_name_prefix}-ExternalSecurityGroup"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
}

resource "azurerm_network_security_rule" "ssh" {
  name                        = "ssh"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = 22
  source_address_prefix       = local.fw_allowed_prefix
  destination_address_prefix  = "*"
  resource_group_name         = data.azurerm_resource_group.rg.name
  network_security_group_name = azurerm_network_security_group.external.name
}

resource "azurerm_subnet_network_security_group_association" "external" {
  subnet_id                 = azurerm_subnet.external.id
  network_security_group_id = azurerm_network_security_group.external.id
}

resource "azurerm_public_ip" "vm_public_ips" {
  for_each = local.vms_configuration

  name                = "${var.resource_name_prefix}${each.key}-PublicIp"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
  allocation_method   = "Static"
}

resource "azurerm_virtual_network" "network" {
  name                = "${var.resource_name_prefix}-Vnet"
  address_space       = [local.network_prefix]
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

  name                  = "${var.resource_name_prefix}${each.key}-Nic"
  resource_group_name   = data.azurerm_resource_group.rg.name
  location              = data.azurerm_resource_group.rg.location
  ip_forwarding_enabled = true

  ip_configuration {
    name                          = "external-ipconfig${each.key}"
    subnet_id                     = azurerm_subnet.external.id
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.ip
    public_ip_address_id          = azurerm_public_ip.vm_public_ips[each.key].id
  }
}

resource "azurerm_managed_disk" "data_disk" {
  for_each = local.vms_configuration

  name                 = "${var.resource_name_prefix}${each.key}-DataDisk"
  location             = data.azurerm_resource_group.rg.location
  resource_group_name  = data.azurerm_resource_group.rg.name
  storage_account_type = "StandardSSD_LRS"
  create_option        = "Empty"
  disk_size_gb         = var.disk_size
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
  availability_set_id = azurerm_availability_set.avail_set.id

  computer_name                   = each.value.hostname
  admin_username                  = "ne_root"
  admin_password                  = random_password.admin_password.result
  disable_password_authentication = false

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
    name                 = "${var.resource_name_prefix}${each.key}-OsDisk"
  }

  network_interface_ids = [azurerm_network_interface.external_nic[each.key].id]

  provisioner "remote-exec" {
    connection {
      type     = "ssh"
      user     = self.admin_username
      password = self.admin_password
      host     = self.public_ip_address
    }

    inline = [
      <<-SH
      %{for vm in local.vms_configuration~}
        echo "${vm.ip} ${format("neteye%02d.neteyelocal", vm.key)}" | sudo tee -a /etc/hosts
        echo "${azurerm_public_ip.vm_public_ips[vm.key].ip_address} ${vm.hostname}" | sudo tee -a /etc/hosts
      %{endfor}
      SH
    ]
  }

  provisioner "remote-exec" {
    connection {
      type     = "ssh"
      user     = self.admin_username
      password = self.admin_password
      host     = self.public_ip_address
    }
    when = destroy
    inline = [
      "sudo subscription-manager unsubscribe --all",
    ]
  }
}


# resource "ansible_host" "ansible_inventory" {
#   count = var.cluster_size
#   name  = azurerm_linux_virtual_machine.vm[count.index].name
#   groups = ["azure", "rhel_hosts"]
#   variables = {
#     ansible_host         = azurerm_public_ip.vm_public_ip[count.index].ip_address
#     ansible_user         = "neteye_service_root"
#     ansible_password     = random_password.admin_password.result
#     neteye_version       = var.neteye_version
#     private_ipv4_address = azurerm_network_interface.external_nic[count.index].private_ip_address
#     provisioner_tag = var.resource_name_prefix
#   }
# }
