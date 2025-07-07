# How to create a NetEye cluster on Azure

## Create resources on Azure using Terraform

> ℹ️ To provision the infrastructure you need to have installed on your PC the `terraform` and `az` (Azure) CLIs.

> ⚠️ Terraform will create a `terraform.tfstate` file, this file contains the configuration of the resources on Azure and some credentials. It must be considered a SECRET and must not be lost.

- You can find the terraform files in `/src/terraform` directory
- Follow this configuration guide to setup the terraform variables, afterwards you can follow the first part of the README.md file to deploy the resources on Azure.

### Terraform variables configuration

You need to create a `*.tfvars` file and put in the following variables:

- `azure_subscription_id`: The Azure subscription ID used to authenticate with Azure. To obtain this value you can follow the login procedure on [Azure Terraform Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/azure_cli). In short:
  - Login on Azure with az login
  - Gather your id by running az account list
  - Put the gathered id value as azure_subscription_id
- `resource_group_name`: The name of the resource group in which the resources will be created.
- `resource_name_prefix`: The prefix for the names of all the resources that will be created, including the VMs.
- `vm_hostname_template`: The template to be used to generate the external hostnames of each VM. It must contain the string %02d where the number of the VM must be written (e.g. `neteye%02d.test.it` for VM 1 will be `neteye01.test.it`).
- `cluster_size`: The number of virtual machines to be created.
- `vm_size`: The size to be used when creating the virtual machines. Check the Azure documentation for valid values.
- `disk_size`: The size of the data disk in GB.

## Configure the VMs to create a Neteye cluster

> ⚠️ There is only one NIC per VM (thus only one subnet). For this reason you must set the NIC as Trusted:
>
> ```sh
> firewall-cmd --set-default-zone trusted
> ```
>
> You can verify by checking the presence of eth0 in the interfaces field after running the following command:
>
> ```sh
> firewall-cmd --zone=trusted --list-all
> ```
>
> The `/etc/hosts` file is already populated with both internal and external IPs.

### 1. Transform RHEL to Neteye

Enable the IPs on `repo.wuerth-phoenix.com`.

> 🗒️ Register with the subscription manager (for this step a dev license should be ok).

> 🗒️ If you are < 4.43 also install _network-scripts_ (`dnf install network-scripts`)

> ⚠️ Disable SELinux:
>
> ```sh
> sed -i 's/SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
> setenforce permissive
> ```

- Remember to set the correct `DNF0` variable
- Run (on all nodes) this script: `src/scripts/rhel-to-neteye.sh`.

> ⚠️ Restart the shell to populate all the new environment variables: `exec bash`

### 2. Follow Neteye Guide until Fencing

> ⚠️ Note that the nodes start from index 00 (and not 01, i.e. neteye00.example.it).

At this point you should have more or less a VM bootstrapped with a Neteye ISO. You can follow the guide at [Cluster Nodes - NetEye User Guide](https://neteye.guide/4.42/getting-started/system-installation/cluster.html).

> ⚠️ When you reach the Cluster Fencing Configuration part please run `dnf install fence-agents-azure-arm` and follow the steps explained in this [Red Hat guide to setup fencing](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/8/html/deploying_rhel_8_on_microsoft_azure/configuring-rhel-high-availability-on-azure_cloud-content-azure#azure-create-a-fencing-device-in-ha_configuring-rhel-high-availability-on-azure).

<u>Afterwards continue with the steps below.</u>

### 3. Set the nic value on cluster_ip

```sh
pcs resource update cluster_ip nic=eth0
```

### 4. Edit and setup cluster templates

> 🗒️ For Non PCS-managed Services you can follow the steps on the guide.

Set the correct `volume_group`, and `10.1.0` as `ip_pre`.

> ⚠️ Don’t change the default ip_post value.

Run the Perl script as described in the Neteye Guide.

### 5. Add azure-lb pcs resources

You can run the `src/ansible/azure-lb-pcs-resources.yml` Ansible playbook (on one node).

> ⚠️ If you run this playbook multiple times, the last two tasks (`Add cluster ip res` and `Add colocation`) will fail on subsequent runs because the resources already exist. This is expected behavior.

### 6. Continue normal configuration

You can continue following the Neteye Guide as usual from [Cluster Nodes - NetEye User Guide](https://neteye.guide/4.42/getting-started/system-installation/cluster.html#ne-service-configuration) onwards.
