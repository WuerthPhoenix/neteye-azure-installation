# How to create a NetEye cluster on Azure

## Create and manage resources on Azure using Terraform

> [!IMPORTANT]
> To provision the infrastructure, you must have both the `terraform` and `az` (Azure) CLI tools installed on your PC.

> [!WARNING]
> Terraform will create a `terraform.tfstate` file, this file contains the configuration of the resources on Azure and some credentials. It must be considered a SECRET and must not be lost.

- The terraform files are in the directory `/src/terraform`.
- Follow this configuration guide to setup the terraform variables, afterwards you can follow the first part of the README.md file to deploy the resources on Azure.

### Terraform variables configuration

1. Login on Azure witn `az login` (follow the login procedure on [Azure Terraform Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/azure_cli)).
2. Gather the Azure subscription ID with `az account list`.
3. Create a file `*.tfvars` with the following content (of course change the variable values as you see fit):

```hcl
azure_subscription_id = "<The Azure subscription ID from the previous step>"

resource_group_name  = "neteye_group"
resource_name_prefix = "neteye_terraform"
cluster_size         = 2
vm_size              = "Standard_E4as_v5"
disk_size            = 256
```

The variables are:

- `azure_subscription_id`: the Azure subscription ID
- `resource_group_name`: the name of the resource group in which the resources will be created.
- `resource_name_prefix`: the prefix for the names of all the resources that will be created, including the VMs.
- `vm_hostname_template`: the template to be used to generate the external hostnames of each VM. It must contain the string %02d where the number of the VM must be written (e.g. `neteye%02d.test.it` for VM 1 will be `neteye01.test.it`).
- `cluster_size`: the number of virtual machines to be created.
- `vm_size`: the size to be used when creating the virtual machines. Check the Azure documentation for valid values.
- `disk_size`: the size of the data disk in GB.

### Provision the resources

To start the provisioning process run the following command:

```sh
terraform apply --var-file "<file defined previously>.tfvars"
```

To get the `ne_root` password use:

```sh
terraform output --raw admin_password
```

### Delete the resources

To start the deletion process run the following command:

```sh
terraform destroy --var-file "<file defined previously>.tfvars"
```

> [!NOTE]
> Try to not change manually the configuration of the created resources, if you
> need to make changes modify the code and open a PR.
>
> To correctly delete the created resources you need to run the `destroy` command
> from the same place that ran the `apply` command (it needs to have the same state
> saved in `terraform.tfstate`).

## Configure the VMs to create a Neteye cluster

> [!WARNING]
> There is only one NIC per VM (thus only one subnet). For this reason you must set the NIC as Trusted:
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

> [!NOTE]
> Register with the subscription manager (for this step a dev license should be ok).
>
> If you are < 4.43 also install _network-scripts_ (`dnf install network-scripts`)

> [!WARNING]
> Disable SELinux:
>
> ```sh
> sed -i 's/SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
> setenforce permissive
> ```

- Remember to set the correct `DNF0` variable
- Run (on all nodes) this script: `src/scripts/rhel-to-neteye.sh`.

> [!WARNING]
> Restart the shell to populate all the new environment variables: `exec bash`

### 2. Follow Neteye Guide until Fencing

> [!WARNING]
> Note that the nodes start from index 00 (and not 01, i.e. `neteye00.example.it`).

At this point you should have more or less a VM bootstrapped with a Neteye ISO. You can follow the guide at [Cluster Nodes - NetEye User Guide](https://neteye.guide/4.42/getting-started/system-installation/cluster.html).

> [!CAUTION]
> Terraform tends to override manual changes to resources if you re-run it. Be conscious of this behavior and ensure any manual steps are documented and reapplied as needed.
> 
> Please see:
> - [Creating an Azure Active Directory application - Red Hat Documentation](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/8/html/deploying_rhel_8_on_microsoft_azure/configuring-rhel-high-availability-on-azure_cloud-content-azure#azure-create-an-azure-directory-application-in-ha_configuring-rhel-high-availability-on-azure)
> - [Creating a fencing device - Red Hat Documentation](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/8/html/deploying_rhel_8_on_microsoft_azure/configuring-rhel-high-availability-on-azure_cloud-content-azure#azure-create-a-fencing-device-in-ha_configuring-rhel-high-availability-on-azure)

> [!WARNING]
> When you reach the Cluster Fencing Configuration part please run `dnf install fence-agents-azure-arm` and follow the steps explained in this [Red Hat guide to setup fencing](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/8/html/deploying_rhel_8_on_microsoft_azure/configuring-rhel-high-availability-on-azure_cloud-content-azure#azure-create-a-fencing-device-in-ha_configuring-rhel-high-availability-on-azure).

<u>Afterwards continue with the steps below.</u>

### 3. Set the nic value on cluster_ip

```sh
pcs resource update cluster_ip nic=eth0
```

### 4. Edit and setup cluster templates

> [!NOTE]
> For Non PCS-managed Services you can follow the steps on the guide.

Set the correct `volume_group`, and `10.1.0` as `ip_pre`.

> [!WARNING]
> Don’t change the default ip_post value.

Run the Perl script as described in the Neteye Guide.

### 5. Add azure-lb pcs resources

You can run the `src/ansible/azure-lb-pcs-resources.yml` Ansible playbook (on one node).

> [!WARNING]
> If you run this playbook multiple times, the last two tasks (`Add cluster ip res` and `Add colocation`) will fail on subsequent runs because the resources already exist. This is expected behavior.

### 6. Continue normal configuration

You can continue following the Neteye Guide as usual from [Cluster Nodes - NetEye User Guide](https://neteye.guide/current/getting-started/system-installation/cluster.html#ne-service-configuration) onwards.
