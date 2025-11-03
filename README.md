# How to create a NetEye cluster on Azure

## Create and manage resources on Azure using Terraform

> [!IMPORTANT]
> To provision the infrastructure, you must have both the `terraform` and `az` (Azure) CLI tools installed on your PC.

> [!WARNING]
> Terraform will create a `terraform.tfstate` file, which contains the configuration of the resources on Azure and some
> credentials. **It must be considered a SECRET and must not be lost**.

> [!WARNING]
> This terraform assumed to used Azure Bring Your Own Subscription for Red Hat. 
> 
> To ensure that your subscription has
> this feature enabled you can run this command:
> ```commandline
> az vm image list --publisher redhat --offer rhel-byos --sku rhel-lvm810-gen2 --all
> ```
> and the output should look like the following:
> ```json
> [
>  {
>    "architecture": "x64",
>    "imageDeprecationStatus": {
>      "imageState": "Active"
>    },
>    "offer": "rhel-byos",
>    "publisher": "RedHat",
>    "sku": "rhel-lvm810-gen2",
>    "urn": "RedHat:rhel-byos:rhel-lvm810-gen2:8.10.2024060517",
>    "version": "8.10.2024060517"
>  }
> ]
> ```
> If you need to use a different one you can change `source_image_reference` and `plan` accordingly to your subscription
> in `main.tf` file.


- The terraform files are kept in the directory `/src/terraform`.
- Follow this configuration guide to setup the terraform variables, afterward you can follow the first part of the
  README.md file to deploy the resources on Azure.

### Terraform variables configuration

#### Prerequisites

If you are using a principal:

- Create or request an Azure Service Principal (follow the login procedure
  on [Azure Provider: Authenticating using a Service Principal with a Client Secret](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/service_principal_client_secret)).
- The principal must have at least the `Network Contributor` and `Virtual Machine Contributor` roles on the subscription
  and resource group you want to use.

#### Configure the variables

1. Navigate to the `cd src/terraform` directory.
2. If it is the first time you use this terraform, run `terraform init` to initialize the working directory.
3. Create a file `*.tfvars` with the following content (make sure you change the variable values as you see fit):

```hcl
azure_client_id     = "<pricipal client id>"
azure_client_secret = "<principal client secret>"
azure_tenant_id     = "<principal tenant id>"
azure_subscription_id = "<principal subscription id>"

resource_group_name  = "neteye_group"
resource_name_prefix = "neteye_terraform"
vm_hostname_template = "neteye%02d.test.it"
cluster_size         = 2
vm_size              = "Standard_E4as_v5"
disk_size            = 256
ssl_certificate_path = "./path/to/certificate.pfx"
```

The variables are:
- `azure_client_id`: Azure Service Principal client ID
- `azure_client_secret`: Azure Service Principal client secret
- `azure_tenant_id`: Azure Service Principal tenant ID
- `azure_subscription_id`: Azure subscription ID
- `resource_group_name`: the name of the resource group in which the resources will be created.
- `resource_name_prefix`: the prefix for the names of all the resources that will be created, including the VMs.
- `vm_hostname_template`: the template to be used to generate the external hostnames of each VM. It must contain the
  string %02d where the number of the VM must be written (e.g. `neteye%02d.test.it` for VM 1 will be
  `neteye01.test.it`).
- `cluster_size`: the number of virtual machines to be created.
- `vm_size`: the size to be used when creating the virtual machines. Check the 
  [Azure documentation](https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/overview) for valid values.
- `disk_size`: the size of the data disk in GB.
- `ssl_certificate_path`: Path to the .pfx SSL certificate to be used for the application gateway.

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
> from the same directory that ran the `apply` command (it needs to have the same state
> saved in `terraform.tfstate`).

### Connecting to the cluster
VMs are not exposed to the internet directly. To connect to them, you must use the Azure Bastion service.
You can do so from the Azure Portal:
1. Navigate to the resource group you created with terraform.
2. Select the `VM` resource you would like to connect to.
3. Click on `Connect` and then select `Bastion`.

## Configure the VMs to create a NetEye cluster
> [!WARNING]
> Before starting, make sure that all the machines are able to read `repo.wuerth-phoenix.com` and that your IP is allowed
> to download NetEye packages. If not, you should request to allow the public ip associated with the NAT gateway

### 1. Transform RHEL to NetEye

> [!NOTE]
> If you are < 4.43 also install _network-scripts_ (`dnf install network-scripts`)

On all nodes:
1. Register the RHEL system:
    ```commandline
    subscription-manager register --org "<organization>" --activationkey "<key>" --name "<your machine name>" --release=8.10 --force

    ```
1. Install `ansible-core` **from NetEye repository** using the right NetEye version for example:
    ```commandline
    dnf install https://repo.wuerth-phoenix.com/rhel8/neteye-4.44-sr1-os/Packages/a/ansible-core-2.13.3-2.el8_7.x86_64.rpm
    ```
2. Clone this repository (or upload the files in `src/ansible/`)
3. Run this playbook: `src/ansible/rhel-to-neteye.yml` passing the NetEye version. For example:
    ```commandline
    ansible-playbook rhel-to-neteye.yml -e neteye_version=4.44
    ```
### 2. Setup basic cluster

At this point you can follow the guide at [Cluster Nodes - NetEye User Guide](https://neteye.guide/current/getting-started/system-installation/cluster.html), remember to properly configure 
the `/etc/hosts` file with the internal IPs. Terraform will automatically generate on your controller a `hosts.txt`
file which contains the lines that you should add.

Make sure to point add the cluster hostname to the `/etc/hosts` file (pointing the clusterIp)
```text
10.1.0.200  myclusterhostname.com
```

> [!IMPORTANT]
> The `ClusterIp` field in the  `/etc/neteye-cluster` should be set to `10.1.0.200`. This will make cluster nodes accept
> traffic coming from the "external" load balancer

> [!WARNING]
> Note that the nodes start from index 00 (and not 01, i.e. `neteye00.example.com`).


> [!CAUTION]
> Terraform tends to override manual changes to resources if you re-run it. Be aware of this behavior and ensure any
> manual steps are documented and reapplied as needed.
>
> Please see:
> - [Creating an Azure Active Directory application - Red Hat Documentation](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/8/html/deploying_rhel_8_on_microsoft_azure/configuring-rhel-high-availability-on-azure_cloud-content-azure#azure-create-an-azure-directory-application-in-ha_configuring-rhel-high-availability-on-azure)
> - [Creating a fencing device - Red Hat Documentation](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/8/html/deploying_rhel_8_on_microsoft_azure/configuring-rhel-high-availability-on-azure_cloud-content-azure#azure-create-a-fencing-device-in-ha_configuring-rhel-high-availability-on-azure)

> [!WARNING]
> When you reach the Cluster Fencing Configuration part please run `dnf install fence-agents-azure-arm` and follow the
> steps explained in
> this [Red Hat guide to setup fencing](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/8/html/deploying_rhel_8_on_microsoft_azure/configuring-rhel-high-availability-on-azure_cloud-content-azure#azure-create-a-fencing-device-in-ha_configuring-rhel-high-availability-on-azure).

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

Run the Perl script
as [described in the NetEye Guide](https://neteye.guide/current/getting-started/system-installation/cluster.html#pcs-managed-services)
to create PCS resources.

### 5. Add azure-lb pcs resources

Upload the playbook `src/ansible/azure-lb-pcs-resources.yml` to **one** machine and run it:

```commandline
ansible-playbook -i localhost, azure-lb-pcs-resources.yml
```

> [!WARNING]
> If you run this playbook multiple times, the last two tasks (`Add cluster ip res` and `Add colocation`) will fail on
> subsequent runs because the resources already exist. This is expected behavior.

### 6. Proceed with regular configuration

You can continue following the NetEye Guide as usual from [Cluster Nodes - NetEye User Guide](https://neteye.guide/current/getting-started/system-installation/cluster.html#ne-service-configuration) onwards. Remember to 
configure timezone etc...
