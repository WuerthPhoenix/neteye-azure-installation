variable "azure_subscription_id" {
  type        = string
  sensitive   = true
  description = "The Azure subscription ID used to authenticate with Azure"
}

variable "azure_client_id" {
  type        = string
  sensitive   = true
  description = "The Azure Principal client ID used to authenticate with Azure"
  default     = null
}

variable "azure_client_secret" {
  type        = string
  sensitive   = true
  description = "The Azure Principal client secret used to authenticate with Azure"
  default     = null
}

variable "azure_tenant_id" {
  type        = string
  sensitive   = true
  description = "The Azure Principal tenant ID used to authenticate with Azure"
  default     = null
}

variable "resource_group_name" {
  type        = string
  description = "The name of the resource group in which the resources will be created."
}

variable "resource_name_prefix" {
  type        = string
  description = "The prefix for the names of all the resources that will be created, including the VMs."
}

variable "vm_hostname_template" {
  type        = string
  description = "The template to be used to generate the external hostnames of each VM. It must contain the string %02d where the number of the VM must be written (e.g. neteye%02d.test.it for VM 1 will be neteye01.test.it)."

  validation {
    condition     = can(regex("%02d", var.vm_hostname_template))
    error_message = "vm_hostname_template should contain a zero-padded two-digit number format specifier (e.g., %02d)"
  }
}

variable "cluster_size" {
  type        = number
  description = "The number of virtual machines to be created."
  validation {
    condition     = var.cluster_size <= 25 && var.cluster_size > 0
    error_message = "cluster_size should be at most 25"
  }
}

variable "vm_size" {
  type        = string
  description = "The size to be used when creating the virtual machines. Check the Azure documentation for valid values."
}

variable "disk_size" {
  type        = number
  description = "The size of the data disk in GB."
  default     = 256
  validation {
    condition     = var.disk_size >= 32 && var.disk_size <= 4096
    error_message = "disk_size should be between 32 and 4096 GB"
  }
}

variable "fw_allowed_ssh_network" {
    type        = string
    description = "Ip range to allow SSH access from."
    default     = "82.193.25.251/32"
}

variable "azure_availability_zones" {
    type        = list(string)
    description = "A list of availability zones to distribute the VMs across."
    default     = ["1", "2", "3"]
}