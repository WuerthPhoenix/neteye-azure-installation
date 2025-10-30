# How to create a NetEye cluster on Azure

## Create and manage resources on Azure using Terraform

> [!IMPORTANT]
> To provision the infrastructure, you must have both the `terraform` and `az` (Azure) CLI tools installed on your PC.

> [!WARNING]
> Terraform will create a `terraform.tfstate` file, which contains the configuration of the resources on Azure and some credentials. It must be considered a SECRET and must not be lost.

- The terraform files are kept in the directory `/src/terraform`.
- Follow this configuration guide to setup the terraform variables, afterwards you can follow the first part of the README.md file to deploy the resources on Azure.

### Terraform variables configuration
#### Prerequisites
If you are using a principal:
- Create or request an Azure Service Principal (follow the login procedure on [Azure Provider: Authenticating using a Service Principal with a Client Secret](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/service_principal_client_secret)).
- The principal must have at least the `Network Contributor` and `Virtual Machine Contributor` roles on the subscription and resource group you want to use.

If you are using user authentication:
1. Login on Azure witn `az login` (follow the login procedure on [Azure Terraform Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/azure_cli)).

#### Configure the variables
1. Gather the Azure subscription ID with `az account list`.
2. Navigate to the `cd src/terraform` directory.
3. If it is the first time you use terraform on this machine, run `terraform init` to initialize the working directory.
4. Create a file `*.tfvars` with the following content (make sure you change the variable values as you see fit):

```hcl
azure_client_id: "<pricipal client id>"
azure_client_secret: "<principal client secret>"
azure_tenant_id: "<principal tenant id>"
azure_subscription_id: "<principal subscription id>"

resource_group_name  = "neteye_group"
resource_name_prefix = "neteye_terraform"
vm_hostname_template = "neteye%02d.test.it"
cluster_size         = 2
vm_size              = "Standard_E4as_v5"
disk_size            = 256
```

The variables are:
- `azure_subscription_id`: Azure subscription ID
- `azure_subscription_id`: Azure subscription ID (only if you are using a principal)
- `azure_client_secret`: Azure Service Principal client secret (only if you are using a principal)
- `azure_tenant_id`: Azure Service Principal tenant ID (only if you are using a principal)
- `resource_group_name`: the name of the resource group in which the resources will be created.
- `resource_name_prefix`: the prefix for the names of all the resources that will be created, including the VMs.
- `vm_hostname_template`: the template to be used to generate the external hostnames of each VM. It must contain the string %02d where the number of the VM must be written (e.g. `neteye%02d.test.it` for VM 1 will be `neteye01.test.it`).
- `cluster_size`: the number of virtual machines to be created.
- `vm_size`: the size to be used when creating the virtual machines. Check the Check the [Azure documentation](https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/overview) for valid values.
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

To start the deletion process — which is handy for cleanup after creating a test
cluster, for example — run the following command:

```sh
terraform destroy --var-file "<file defined previously>.tfvars"
```

> [!NOTE]
> Try not to change the configuration of the created resources manually, if you
> need to make changes modify the code and open a PR.
>
> To correctly delete the created resources you need to run the `destroy` command
> from the same place that ran the `apply` command (it needs to have the same state
> saved in `terraform.tfstate`).

## Configure the VMs to create a NetEye cluster

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

### 1. Transform RHEL to NetEye

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

Run (on all nodes) this script: `src/scripts/rhel-to-neteye.sh` passing the NetEye version. For example:
```sh
rhel-to-neteye.sh 4.43
```

> [!WARNING]
> Restart the shell to populate all the new environment variables: `exec bash`

### 2. Setup basic cluster

At this point you can follow the guide at [Cluster Nodes - NetEye User Guide](https://neteye.guide/current/getting-started/system-installation/cluster.html), remember to 
properly configure the `/etc/hosts` file with the internal IPs. Should looks like this:
```commandline
[...]
10.1.0.4 neteye00.neteyelocal neteye00.example.com neteye00
10.1.0.5 neteye01.neteyelocal neteye01.example.com neteye01
10.1.0.6 neteye02.neteyelocal neteye02.example.com neteye02
<public_ip> neteye.example.com neteye.neteyelocal
```

> [!WARNING]
> Note that the nodes start from index 00 (and not 01, i.e. `neteye00.example.it`).
> 
> The public IP does not really matter on azure, since we are using a load balancer, but it is required
> to successfully complete the `neteye install`


> [!CAUTION]
> Terraform tends to override manual changes to resources if you re-run it. Be aware of this behavior and ensure any manual steps are documented and reapplied as needed.
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

### 4. Setup cluster resources

Configure LVM with the wanted configuration, for example:

```sh
vgcreate vg00 /dev/sdb
vgs
```

> [!NOTE]
> For Non PCS-managed Services you can follow the steps on the guide.

Set the correct `volume_group`, and `10.1.0` as `ip_pre`.

> [!WARNING]
> Don’t change the default ip_post value and do not run the `neteye install` command.

Run the Perl script as [described in the NetEye Guide](https://neteye.guide/current/getting-started/system-installation/cluster.html#pcs-managed-services) to create PCS resources.


### 5. Add azure-lb pcs resources

Upload the playbook `src/ansible/azure-lb-pcs-resources.yml` to **one** machine and run it:
```commandline
ansible-playbook -i localhost, azure-lb-pcs-resources.yml
```

> [!WARNING]
> If you run this playbook multiple times, the last two tasks (`Add cluster ip res` and `Add colocation`) will fail on subsequent runs because the resources already exist. This is expected behavior.

### 6. Proceed with regular configuration

You can continue following the NetEye Guide as usual from [Cluster Nodes - NetEye User Guide](https://neteye.guide/current/getting-started/system-installation/cluster.html#ne-service-configuration) onwards.
