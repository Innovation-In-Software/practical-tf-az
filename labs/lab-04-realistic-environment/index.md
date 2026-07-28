# Lab 4: A Realistic Environment

## Overview

Three resources is a demo. A real ticket says "stand up the Orders dev
environment," and that means networking, a machine, somewhere to put data, and
consistent tags so finance and security can tell what it is.

In this lab you grow Lab 3's foundation into an environment somebody could
actually hand to a developer:

- a **network security group (NSG)** on the subnet, with one rule that lets you
  in and nothing else
- a **Linux virtual machine**, which turns out to be four resources, not one
- a **storage account** with a container
- the same tags on everything, applied from one place

You also meet your first input variable, because a VM needs an admin password
and passwords do not belong in files.

## Objectives

By the end of this lab you can:

- Provision an NSG with a security rule and associate it with a subnet
- Explain why one virtual machine requires a public IP, a network interface,
  and a VM resource
- Provision a storage account and container, and handle the global name
  uniqueness rule
- Declare an input variable, mark it sensitive, and supply it without writing it
  into a file
- Apply a consistent tag set and naming pattern across an environment

## What you'll need

- Your repository from Lab 3, with the resource group, VNet, and subnet applied
- `ARM_SUBSCRIPTION_ID` set
- Your 4-character student suffix

> **This lab drives VS Code rather than the command line wherever VS Code can do
> the job:** branching, creating files, formatting, reading your own diff,
> committing, and opening the pull request. The equivalent commands are shown
> underneath each one, because pipelines and error messages speak in commands and
> you need to recognize them.
>
> Terraform itself has no buttons. `init`, `validate`, `plan`, and `apply` are
> always typed into the integrated terminal, and so is anything setting an
> environment variable.

### Start clean

Same pattern as Lab 2, now as habit: get onto `main`, pull, then branch.

1. Open your repository in VS Code if it is not already open:
   **File > Open Recent**, and pick `az-tf-ops-<your-username>`.
2. **Get onto `main`.** Click the branch name in the bottom left status bar and
   choose `main` from the list.
3. **Pull.** Click the sync icon (the circular arrows) next to the branch name in
   the status bar. This brings down the Lab 3 change you merged.
4. **Branch.** Click the branch name again, choose **Create new branch...**, and
   name it:

   ```
   feature/lab04-orders-dev-environment
   ```

5. Confirm the status bar now shows `feature/lab04-orders-dev-environment`. If it
   still says `main`, you are about to commit to the shared branch. Go back to
   step 4.

The command line equivalent, which is what those buttons run:

```powershell
cd C:\Users\Administrator\Downloads\terraform\labs\az-tf-ops-<your-username>
git switch main
git pull
git switch -c feature/lab04-orders-dev-environment
```

### Confirm Lab 3 is still good

Terraform has no VS Code buttons, so open a terminal for this one:
``Ctrl+` ``, or right-click the repository folder in the Explorer and choose
**Open in Integrated Terminal**.

```powershell
terraform plan
```

That plan must say **No changes** before you start. If it does not, fix Lab 3
first.

## Part 1: Lock down the subnet with an NSG

A **network security group (NSG)** is a list of allow and deny rules for traffic
in and out of a subnet or network interface. It is the most common place an ops
team accidentally locks itself out, and the most common place an environment is
accidentally left open.

Add to `main.tf`:

```hcl
resource "azurerm_network_security_group" "orders" {
  name                = "nsg-summit-orders-dev"
  resource_group_name = azurerm_resource_group.orders.name
  location            = azurerm_resource_group.orders.location

  tags = azurerm_resource_group.orders.tags
}

resource "azurerm_network_security_rule" "ssh" {
  name                        = "AllowSSHFromAdmin"
  resource_group_name         = azurerm_resource_group.orders.name
  network_security_group_name = azurerm_network_security_group.orders.name

  priority                   = 100
  direction                  = "Inbound"
  access                     = "Allow"
  protocol                   = "Tcp"
  source_port_range          = "*"
  destination_port_range     = "22"
  source_address_prefix      = var.allowed_ssh_source
  destination_address_prefix = "*"
}

resource "azurerm_subnet_network_security_group_association" "app" {
  subnet_id                 = azurerm_subnet.app.id
  network_security_group_id = azurerm_network_security_group.orders.id
}
```

Three things to notice.

**Three resources for one idea.** An NSG, a rule in it, and the attachment of
the NSG to a subnet. Creating an NSG does nothing until it is associated with
something, and an NSG with no rules only carries Azure's invisible defaults.

**Rules can be written two ways, and you must pick one.** Azure lets you nest
`security_rule { ... }` blocks inside the `azurerm_network_security_group`
resource, or declare each rule as a separate `azurerm_network_security_rule`.
We use separate resources, because adding a rule is then a new block rather than
an edit to an existing one, which makes for a smaller and clearer pull request.
Summit's shared modules do the same, which matters in Lab 12.

**Never mix the two styles on one NSG.** They will fight on every apply, each
removing what the other added. Pick separate resources and stay with them.

**`priority = 100`** decides rule order: lower numbers evaluate first. Azure adds
invisible default rules at priorities 65000 and up, which deny inbound from the
internet and allow everything within the VNet. Your rule at 100 is evaluated
long before those.

> `source_address_prefix = var.allowed_ssh_source` refers to a variable you have
> not declared yet. `terraform validate` will complain until Part 3. That is
> fine, keep going.

## Part 2: The virtual machine (which is four resources)

In the portal, "create a virtual machine" is one wizard. In Terraform, and in
the Azure API underneath, it is several objects and you have to know they exist:

| Resource | Why it exists |
|---|---|
| `azurerm_public_ip` | A routable address, so you can SSH in from outside |
| `azurerm_network_interface` | The NIC that joins the VM to the subnet and holds its IP configuration |
| `azurerm_linux_virtual_machine` | The machine itself: size, image, credentials |
| the OS disk | Created implicitly by the VM's `os_disk` block |

Add all of them:

```hcl
resource "azurerm_public_ip" "app" {
  name                = "pip-summit-orders-dev"
  resource_group_name = azurerm_resource_group.orders.name
  location            = azurerm_resource_group.orders.location
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = azurerm_resource_group.orders.tags
}

resource "azurerm_network_interface" "app" {
  name                = "nic-summit-orders-dev"
  resource_group_name = azurerm_resource_group.orders.name
  location            = azurerm_resource_group.orders.location

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.app.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.app.id
  }

  tags = azurerm_resource_group.orders.tags
}

resource "azurerm_linux_virtual_machine" "app" {
  name                = "vm-summit-orders-dev"
  resource_group_name = azurerm_resource_group.orders.name
  location            = azurerm_resource_group.orders.location
  size                = "Standard_F1als_v7"

  admin_username                  = "azureuser"
  admin_password                  = var.vm_admin_password
  disable_password_authentication = false

  network_interface_ids = [
    azurerm_network_interface.app.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  tags = azurerm_resource_group.orders.tags
}
```

A few details that trip people up:

**`disable_password_authentication = false`** is required whenever you use
`admin_password`. The provider defaults it to `true`, because SSH keys are the
better practice. We use a password here so that Lab 8 has something to move into
Key Vault.

**`network_interface_ids` is a list.** A VM can have more than one NIC. Even with
one, the brackets are required.

**`version = "latest"`** on the image sounds convenient and is a mild production
hazard: the image can move under you and a rebuilt VM is not identical to the
original. Pin a specific image version in real production. We use `latest` here
so the lab does not break when Canonical retires an image.

**`Standard_F1als_v7`** is a small, inexpensive size: one vCPU and 2 GB of
memory. Plenty for this.

> Most Azure tutorials you find online use `Standard_B1s`, the burstable size
> that used to be the default choice for a small VM. Your class subscription
> does not offer the B series, so that size fails with `SkuNotAvailable`. This
> is worth knowing beyond the classroom: **VM sizes are not uniformly available**.
> What exists depends on the region and on your subscription's offer, and
> checking is one command:
>
> ```powershell
> az vm list-skus --location eastus --resource-type virtualMachines --query "[?name=='Standard_F1als_v7']" -o table
> ```

## Part 3: Declare the variables

The NSG rule and the VM both reference variables. Declare them now.

Create the file in VS Code: hover over the repository name at the top of the
**Explorer** panel and click the **New File...** icon (a page with a `+`), then
type `variables.tf` and press Enter. Make sure it lands at the top level of the
repository, next to `main.tf`, not inside another folder.

> Watch the bottom right of the window after you name it. It should say
> **Terraform**. That is VS Code recognizing the `.tf` extension and switching on
> the HashiCorp extension's syntax highlighting and autocomplete. If it says
> **Plain Text**, you have a typo in the file name.

Put this in it:

```hcl
variable "vm_admin_password" {
  description = "Admin password for the Orders dev VM. Supplied at run time, never stored in the repo."
  type        = string
  sensitive   = true
}

variable "allowed_ssh_source" {
  description = "The single public IP address allowed to reach the VM on port 22, in CIDR form."
  type        = string
}
```

Neither has a `default`, which means Terraform will refuse to run until you
supply a value. That is the point.

`sensitive = true` on the password tells Terraform to redact the value in plan
and apply output. Be clear about what it does and does not do:

- It **does** stop the value appearing in your terminal and in CI logs
- It **does not** encrypt anything. The password lands in `terraform.tfstate` in
  plain text regardless

That second point is why Lab 5 moves state somewhere access-controlled and Lab 8
stops putting the secret in a variable at all.

### Supply the values

The obvious move, writing them into a `.tfvars` file and committing it, is
exactly the mistake this course exists to prevent. Use environment variables
instead. Terraform reads any variable named `TF_VAR_<variable name>`.

First find your own public IP address, so the NSG rule lets you and only you in:

```powershell
$myip = (Invoke-RestMethod https://api.ipify.org)
$env:TF_VAR_allowed_ssh_source = "$myip/32"
$env:TF_VAR_allowed_ssh_source
```

On macOS or Linux:

```sh
export TF_VAR_allowed_ssh_source="$(curl -s https://api.ipify.org)/32"
```

Then set a password. Azure requires 12 to 72 characters with three of: lower
case, upper case, a digit, a symbol.

```powershell
$env:TF_VAR_vm_admin_password = "Summit-Lab-2026!"
```

> Yes, that password is now in your shell history, and yes, that is also a bad
> habit. It is a deliberate stepping stone: Lab 8 removes the variable entirely
> and reads the value from Key Vault at apply time.

> **`/32` matters.** It means "exactly this one address." A tired engineer types
> `0.0.0.0/0` to make an SSH problem go away and opens the machine to the whole
> internet. If your address changes (VPN, coffee shop, reconnected VM), rerun
> the two commands above and `terraform apply` again.

## Part 4: Storage

```hcl
resource "azurerm_storage_account" "orders" {
  # CHANGE THIS: replace <suffix> with your 4-character student suffix.
  # Storage account names are globally unique across all of Azure,
  # 3-24 characters, lowercase letters and digits only. No hyphens.
  name                     = "stsummitordersdev<suffix>"
  resource_group_name      = azurerm_resource_group.orders.name
  location                 = azurerm_resource_group.orders.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  tags = azurerm_resource_group.orders.tags
}

resource "azurerm_storage_container" "data" {
  name                  = "orders-data"
  storage_account_id    = azurerm_storage_account.orders.id
  container_access_type = "private"
}
```

Replace `<suffix>` with yours. If you skip this, you will get
`StorageAccountAlreadyTaken` and now you know why.

> **A faster way to do that replacement, and a habit worth forming.** Press
> `Ctrl+H` to open Find and Replace in the current file. Put `<suffix>` in the
> top box and your four characters in the bottom, then click **Replace All** (or
> `Ctrl+Alt+Enter`). Use `Ctrl+Shift+H` to do the same across every file in the
> repository at once, which is what you will want in Lab 6.

`account_replication_type = "LRS"` is locally redundant storage: three copies in
one datacenter. It is the cheapest option and correct for a dev environment.
Production would use `ZRS` or `GRS`, and in Lab 6 that difference becomes a
variable rather than an edit.

> Note `storage_account_id` rather than `storage_account_name`. Version 4 of the
> provider deprecated the name form. If you copy an example from a blog post
> written against version 3, this is one of the arguments that will have moved.

## Part 5: Add an output

You will want the VM's public IP address, and hunting for it in the portal every
time is silly.

Create `outputs.tf` the same way you created `variables.tf`: **New File...** in
the Explorer, at the top level of the repository.

```hcl
output "vm_public_ip" {
  description = "Public IP address of the Orders dev VM."
  value       = azurerm_public_ip.app.ip_address
}

output "vm_ssh_command" {
  description = "Copy and paste this to connect."
  value       = "ssh azureuser@${azurerm_public_ip.app.ip_address}"
}

output "storage_account_name" {
  description = "Name of the Orders dev storage account."
  value       = azurerm_storage_account.orders.name
}
```

`"${...}"` is string interpolation: everything inside the braces is an
expression, and its result is substituted into the string. You will use it
constantly in Lab 6.

## Part 6: Apply

### Format from VS Code

You ran `terraform fmt` from the terminal in Lab 3. VS Code can do it for you:
with a `.tf` file open, press `Shift+Alt+F` (**Format Document**). The HashiCorp
extension aligns the `=` signs and fixes the indentation in place.

Better, make it automatic. Press `Ctrl+,` to open Settings, search for
**Format On Save**, and tick it. Every save is now formatted, and you never think
about `terraform fmt` again.

> If `Shift+Alt+F` asks you to pick a formatter, choose **HashiCorp Terraform**.
> If nothing happens at all, the extension is not active on this file: check the
> language indicator in the bottom right says **Terraform**.

The command line still works and is what the pipeline uses in Lab 10, so it is
worth knowing both:

```powershell
terraform fmt
```

### Validate and plan

These have no VS Code equivalent. Back to the terminal:

```powershell
terraform validate
terraform plan
```

The plan should report **8 to add, 0 to change, 0 to destroy**: NSG, the SSH
rule, the association, public IP, NIC, VM, storage account, and container. Your
three existing resources are untouched, and it should say so by not mentioning
them.

Scroll to the VM block in the plan output. `admin_password` shows as
`(sensitive value)`. That is `sensitive = true` doing its job.

```powershell
terraform apply
```

Type `yes`. The VM takes a minute or two. At the end you get the outputs:

```
Outputs:

storage_account_name = "stsummitordersdevjr42"
vm_public_ip = "20.121.44.7"
vm_ssh_command = "ssh azureuser@20.121.44.7"
```

## Part 7: Verify

### Connect to the VM

```powershell
ssh azureuser@<the ip from your output>
```

Accept the host key with `yes`, then enter the password you set in
`TF_VAR_vm_admin_password`. You should land on an Ubuntu prompt. Type `exit` to
leave.

If it hangs, your NSG rule is the first suspect. See the troubleshooting table.

### Prove the NSG is doing something

While still in PowerShell, try a port the NSG does not allow:

```powershell
Test-NetConnection -ComputerName <the ip> -Port 80
```

It fails. Nothing is listening on port 80, but more importantly the NSG would
have dropped it anyway. Default-deny is the behavior you want.

### Look at the whole environment

In the portal, open `rg-summit-orders-dev`. You now see eight or so items,
including the OS disk that Terraform created implicitly. Click **Tags** on a few
of them: every one carries the same four tags, spelled the same way, because
they all reference one map.

Then run:

```powershell
terraform state list
```

Eleven resources. Compare that to the portal's view and notice two differences.
The OS disk is not in the list, because Terraform manages it as part of the VM
rather than as a separate address. And the NSG rule and the subnet association
are in the list but are not separate items in the portal, because Azure models
them as parts of their parents. **The portal's view and Terraform's view of the
same environment do not line up one to one**, which is worth remembering the
first time a count surprises you.

## Part 8: Commit

All of this is the Lab 2 loop, run from the **Source Control** panel (the
branching icon in the activity bar).

### Read your own diff first

1. Open the Source Control panel. Under **Changes** you should see three entries:
   `main.tf`, `variables.tf`, and `outputs.tf`.
2. **Click `main.tf`.** VS Code opens a side-by-side diff: your original Lab 3
   file on the left, the new version on the right. Read it.

This is the habit worth taking away from Lab 4. You are about to ask a colleague
to review 60 lines that create a VM and open a firewall port. Read it yourself
first, the way they will.

While you are looking, confirm what is **not** listed: no `terraform.tfstate`, no
`.terraform/`, no `.terraform.lock.hcl` changes you did not expect. If state
appears here, stop and tell the instructor, because the `.gitignore` is not doing
its job.

### Stage, commit, push

3. Hover over **Changes** and click the **+** to stage all three files at once.
4. In the message box, write:

   ```
   Add NSG, Linux VM, and storage to the orders dev environment
   ```

5. Click the **Commit** checkmark.
6. Click **Publish Branch**.

### Open the pull request

7. Click the **GitHub** icon in the activity bar, then **Create Pull Request**.
8. Check the base is **your** repository's `main`, not the organization's.
9. Title it the same as the commit, describe it in a sentence, and click
   **Create**.
10. Open **Files Changed** and look at the diff as a reviewer sees it. This is a
    substantial change, exactly the kind a teammate should read.
11. Merge it from the pull request view or the GitHub web page.

### Get back onto main

12. Click the branch name in the status bar, choose `main`, then click the sync
    icon to pull the merge down.

The command line equivalent for the whole of Part 8:

```powershell
git add main.tf variables.tf outputs.tf
git commit -m "Add NSG, Linux VM, and storage to the orders dev environment"
git push -u origin feature/lab04-orders-dev-environment
# open, review, and merge the pull request, then:
git switch main
git pull
```

Confirm the Source Control panel shows no pending changes, and that neither
`terraform.tfstate` nor `.terraform/` was committed.

## Reflect

Talk these through:

1. Your configuration hardcodes `Standard_F1als_v7`, `LRS`, and `10.10.0.0/16`. What
   has to happen when you need a production copy of this environment? (Lab 6.)
2. `terraform.tfstate` is on your VM's disk. What happens when a teammate needs
   to change this environment? (Lab 5.)
3. The VM password is in your shell history and in state. Where should it live?
   (Lab 8.)

Those three questions are the rest of Day 2.

## How to verify

- [ ] `terraform plan` reports **No changes**
- [ ] `terraform state list` shows 11 resources
- [ ] You can SSH to the VM using the `vm_ssh_command` output
- [ ] Every resource in the portal carries the four standard tags
- [ ] Your branch is merged into `main`

## If you get stuck

| Error | What it means and what to do |
|---|---|
| `StorageAccountAlreadyTaken` | You left `<suffix>` in the name, or your suffix collides. Change it, `terraform apply` again. |
| `The storage account named ... is invalid` | Uppercase letters or hyphens in the name. Lowercase and digits only, 3-24 characters. |
| `no value for required variable` | `TF_VAR_vm_admin_password` or `TF_VAR_allowed_ssh_source` is not set in **this** terminal. |
| SSH connection times out | Your public IP changed. Run the `ipify` command again, reset `TF_VAR_allowed_ssh_source`, and `terraform apply`. Then confirm the rule in the portal under the NSG's **Inbound security rules**. |
| SSH says `Permission denied` | The password is wrong, or it did not meet Azure complexity rules and the VM took a different one. Reset it in the portal under the VM's **Reset password**, or destroy and recreate the VM. |
| `Password not complex enough` on apply | 12-72 characters, and three of: lowercase, uppercase, digit, symbol. |
| `SkuNotAvailable` for `Standard_F1als_v7` | Your subscription does not offer that size in this region. Confirm with `az vm list-skus --location eastus --resource-type virtualMachines --query "[?name=='Standard_F1als_v7']" -o table`. If it comes back empty, tell the instructor. `Standard_D2als_v7` is the fallback. Changing region rarely helps, because the restriction usually comes from the subscription rather than the region. |
| Plan wants to replace the VM you just built | You changed something immutable, such as the image or the admin username. Read the `# forces replacement` note in the plan. |

## Cleanup

**Leave the environment running.** Lab 5 migrates its state to a shared backend,
and that is far more interesting with real resources behind it.

Do stop the VM at the end of the day so it does not bill for compute overnight:

```powershell
az vm deallocate --resource-group rg-summit-orders-dev --name vm-summit-orders-dev
```

Start it again tomorrow morning:

```powershell
az vm start --resource-group rg-summit-orders-dev --name vm-summit-orders-dev
```

Deallocating does not change anything Terraform manages, so your next `plan`
still reports no changes.

## Congratulations!

That is Day 1. You went from clicking through the portal to standing up a
tagged, network-secured, code-defined environment that you can rebuild from a
file in about three minutes.

It also has three real problems: the state is on your laptop, the values are
hardcoded, and there is a password in your shell history. Day 2 fixes all three,
in that order.
