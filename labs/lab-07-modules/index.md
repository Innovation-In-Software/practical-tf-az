# Lab 7: Consuming Modules Across Repositories

## Overview

Summit's platform team maintains vetted Terraform modules in a separate
repository, `az-tf-ops-modules`. Every solution team uses them. Nobody writes
their own virtual network resources any more, because the platform team already
worked out the NSG associations, the naming, and the security defaults.

Your job on the Orders team is to be a good **consumer** of those modules: read
their inputs, wire their outputs together, pin their versions, and open an issue
instead of forking when something is missing.

In this lab you build Summit's **production** environment entirely from shared
modules. Prod is currently an empty resource group, so this is a clean build,
and by the end you will have two working environments produced from two very
different styles of configuration:

| | `environments/dev` | `environments/prod` |
|---|---|---|
| Built in | Labs 3-6 | This lab |
| Style | resources written inline | module calls |
| Lines of HCL | about 130 | about 60 |

Dev catches up in Lab 12, using a technique you do not have yet.

## Objectives

By the end of this lab you can:

- Explain what a module is and the difference between a root and a child module
- Source a module from a subdirectory of a Git repository
- Pin a module version with `?ref=` and say why an unpinned module is a hazard
- Read a module you did not write and work out what to pass it
- Wire one module's output into another module's input
- Read the plan produced by changing a module version

## What you'll need

- Your repository with Lab 6 merged
- The shared modules repository:
  [github.com/Innovation-In-Software/az-tf-ops-modules](https://github.com/Innovation-In-Software/az-tf-ops-modules)
- Your suffix, and the usual environment variables

```powershell
cd C:\labs\az-tf-ops-<your-username>
git switch main
git pull
git switch -c feature/lab07-prod-from-modules

$env:TF_VAR_allowed_ssh_source = "$(Invoke-RestMethod https://api.ipify.org)/32"
$env:TF_VAR_vm_admin_password = "Summit-Prod-2026!"
```

## Part 1: Read the modules before you use them

This is the actual skill. Open the repository in your browser:
[github.com/Innovation-In-Software/az-tf-ops-modules](https://github.com/Innovation-In-Software/az-tf-ops-modules)

```
az-tf-ops-modules/
  README.md
  network/
    README.md
    main.tf
    variables.tf
    outputs.tf
  linux-vm/
    ...
  storage/
    ...
```

One repository, three modules, each in its own subdirectory. This is a common
layout: it means one place to review changes and one set of release tags,
instead of three repositories to keep in step.

For any module you have not used before, read three files in this order:

1. **`README.md`** for the summary and a usage example
2. **`variables.tf`** for the real, authoritative list of inputs: their types,
   which have defaults (optional) and which do not (required), and the
   `description` on each
3. **`outputs.tf`** for what you get back, which is how you wire modules
   together

Do that now for `network`. Answer these before continuing:

- Which inputs are required?
- What does the module name the subnets it creates?
- What does `subnet_ids` give you back, and what shape is it?

<!-- screenshot: az-tf-ops-modules repo, network/variables.tf on GitHub -> images/module-variables.png -->

> **Do not read `main.tf` first.** A module's interface is its variables and
> outputs. If you find yourself reading the implementation to work out how to
> call it, that is a documentation bug worth raising as an issue.

### Root modules and child modules

Every directory you run `terraform apply` in is a **root module**.
`environments/prod` is a root module. A module it calls is a **child module**.
Child modules get their provider configuration from the root, which is why the
shared modules declare `required_providers` but never a `provider` block.

## Part 2: Write the production configuration

Replace the whole contents of `environments/prod/main.tf` with this. Note it
still creates the resource group directly: a resource group is a one-liner and
does not earn a module.

```hcl
terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
}

locals {
  name_prefix = "${var.org}-${var.solution}-${var.environment}"

  tags = {
    environment = var.environment
    solution    = var.solution
    owner       = var.owner
    managed_by  = "terraform"
  }
}

resource "azurerm_resource_group" "orders" {
  name     = "rg-${local.name_prefix}"
  location = var.location
  tags     = local.tags
}

# ---------------------------------------------------------------------------
# Network: virtual network, subnets, NSG, rules, and the subnet associations.
# ---------------------------------------------------------------------------
module "network" {
  source = "git::https://github.com/Innovation-In-Software/az-tf-ops-modules.git//network?ref=v1.0.0"

  name_prefix         = local.name_prefix
  resource_group_name = azurerm_resource_group.orders.name
  location            = var.location
  address_space       = var.vnet_address_space

  subnets = {
    app  = { address_prefix = cidrsubnet(var.vnet_address_space[0], 8, 1) }
    data = { address_prefix = cidrsubnet(var.vnet_address_space[0], 8, 2) }
  }

  inbound_rules = {
    AllowSSHFromAdmin = {
      priority               = 100
      protocol               = "Tcp"
      destination_port_range = "22"
      source_address_prefix  = var.allowed_ssh_source
    }
  }

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Compute. subnet_id comes straight out of the network module's output.
# ---------------------------------------------------------------------------
module "app_vm" {
  source = "git::https://github.com/Innovation-In-Software/az-tf-ops-modules.git//linux-vm?ref=v1.0.0"

  name_prefix         = local.name_prefix
  resource_group_name = azurerm_resource_group.orders.name
  location            = var.location
  subnet_id           = module.network.subnet_ids["app"]

  vm_size        = var.vm_size
  admin_password = var.vm_admin_password

  tags = merge(local.tags, { role = "app-server" })
}

# ---------------------------------------------------------------------------
# Storage.
# ---------------------------------------------------------------------------
module "storage" {
  source = "git::https://github.com/Innovation-In-Software/az-tf-ops-modules.git//storage?ref=v1.0.0"

  name_prefix         = local.name_prefix
  name_suffix         = var.storage_name_suffix
  resource_group_name = azurerm_resource_group.orders.name
  location            = var.location

  containers = {
    "orders-data" = { access_type = "private" }
    "orders-logs" = { access_type = "private" }
  }

  tags = local.tags
}
```

### Reading a module source string

```
git::https://github.com/Innovation-In-Software/az-tf-ops-modules.git//network?ref=v1.0.0
^^^^^                                                                ^^^^^^^^ ^^^^^^^^^^
|                                                                    |        |
|                                                                    |        the version tag
|                                                                    the subdirectory
the protocol: fetch this with git, over https
```

The double slash is not a typo and it is not a path separator. It marks where
the repository URL ends and the path inside it begins. Getting this wrong
produces `module not found`, and it is nearly always a missing or misplaced
`//`.

Because the repository is public, HTTPS needs no credentials. A private modules
repository would use `git::ssh://git@github.com/...` with an SSH key, or an
HTTPS URL with a token, which is one more reason teams keep modules public
inside the organization.

### Wiring modules together

```hcl
subnet_id = module.network.subnet_ids["app"]
```

`module.<name>.<output>` reads an output from another module call. Because
`subnet_ids` is a map keyed by subnet short name, `["app"]` picks one.

This single line also creates the dependency: Terraform knows the network must
exist before the VM, because the VM's input reads the network's output. You did
not declare an ordering, and you should not need to.

## Part 3: Add the prod variables

`environments/prod/variables.tf` currently has five variables. Add the ones the
modules need:

```hcl
variable "vnet_address_space" {
  description = "Address space for the production virtual network."
  type        = list(string)
}

variable "vm_size" {
  description = "Azure VM size for the production application server."
  type        = string
  default     = "Standard_D2als_v7"
}

variable "vm_admin_password" {
  description = "Admin password for the production VM. Supplied at run time."
  type        = string
  sensitive   = true
}

variable "allowed_ssh_source" {
  description = "The one public IP allowed to reach the VM on port 22, in CIDR form."
  type        = string

  validation {
    condition     = can(cidrhost(var.allowed_ssh_source, 0))
    error_message = "allowed_ssh_source must be valid CIDR notation."
  }
}

variable "storage_name_suffix" {
  description = "Your 4-character student suffix, for global storage account uniqueness."
  type        = string
}
```

And update `environments/prod/prod.tfvars`:

```hcl
environment         = "prod"
location            = "eastus"
vnet_address_space  = ["10.20.0.0/16"]
vm_size             = "Standard_D2als_v7"
storage_name_suffix = "<suffix>"
```

Replace `<suffix>`.

Prod uses `10.20.0.0/16` where dev uses `10.10.0.0/16`, so the two networks
could be peered later without an address collision. Prod gets `Standard_D2als_v7`
where dev gets `Standard_F1als_v7`. **This is the payoff of Lab 6 and Lab 5
together:** two environments, different sizes and address spaces, no duplicated
resource definitions and no shared state.

## Part 4: Init, and watch modules download

```powershell
cd environments\prod
terraform init
```

```
Initializing modules...
Downloading git::https://github.com/Innovation-In-Software/az-tf-ops-modules.git?ref=v1.0.0 for app_vm...
- app_vm in .terraform/modules/app_vm/linux-vm
Downloading git::... for network...
- network in .terraform/modules/network/network
Downloading git::... for storage...
- storage in .terraform/modules/storage/storage
```

Modules are fetched at `init` time and cached under `.terraform/modules/`. Look
in there: it is a full clone of the modules repository at that tag.

Two consequences worth knowing:

- **Editing files under `.terraform/modules/` does nothing useful.** The next
  `init` overwrites them. To change module behavior, change your inputs, or ask
  the platform team.
- **`terraform init` is when a module version can change.** If you had not
  pinned `?ref=`, this command would silently pick up whatever is on `main`
  right now. Nobody edited your configuration, but your infrastructure would be
  different. That is the "my prod broke and I did not change anything" story.

## Part 5: Plan and apply

```powershell
terraform plan -var-file=prod.tfvars
```

Read the resource addresses. They now look like:

```
  # module.network.azurerm_virtual_network.this will be created
  # module.network.azurerm_subnet.this["app"] will be created
  # module.app_vm.azurerm_linux_virtual_machine.this will be created
  # module.storage.azurerm_storage_account.this will be created
```

`module.<call name>.<resource type>.<resource name>` and, for a `for_each`
resource, the key. Module calls nest in the address, which is how Terraform
keeps two calls to the same module apart.

You should see **12 to add**. Then:

```powershell
terraform apply -var-file=prod.tfvars
```

## Part 6: Add outputs from module outputs

Create `environments/prod/outputs.tf`:

```hcl
output "resource_group_name" {
  value       = azurerm_resource_group.orders.name
  description = "Name of the production resource group."
}

output "vm_ssh_command" {
  value       = module.app_vm.ssh_command
  description = "Ready-to-paste SSH command for the production VM."
}

output "vm_private_ip" {
  value       = module.app_vm.private_ip_address
  description = "Private IP of the production VM."
}

output "subnet_ids" {
  value       = module.network.subnet_ids
  description = "Map of subnet short name to resource ID."
}

output "storage_account_name" {
  value       = module.storage.storage_account_name
  description = "Name of the production storage account."
}
```

A module's outputs are not automatically your outputs. If you want to see a
value at the top level, or feed it to a pipeline, you re-export it like this.

```powershell
terraform apply -var-file=prod.tfvars
terraform output
```

Verify the environment:

```powershell
ssh azureuser@<the IP from vm_ssh_command>
```

and check the portal: `rg-summit-orders-prod` should contain a VNet with two
subnets, an NSG with one rule, a VM, and a storage account with two containers.

## Part 7: The version pin, and why it exists

Right now you are pinned to `v1.0.0`. The platform team has since released
`v1.1.0`. Read what changed:

Open
[the modules repository releases](https://github.com/Innovation-In-Software/az-tf-ops-modules/releases)
and the `storage` module README section "Upgrading from v1.0.0 to v1.1.0".

The short version: v1.0.0's storage module allowed TLS 1.0 and hardcoded LRS
redundancy. v1.1.0 raises the TLS floor to 1.2, disables public access to
nested items, and exposes `account_tier` and `replication_type` as inputs.

Bump only the storage module's pin:

```hcl
module "storage" {
  source = "git::https://github.com/Innovation-In-Software/az-tf-ops-modules.git//storage?ref=v1.1.0"
  ...
}
```

A new module version means a new `init`:

```powershell
terraform init -upgrade
terraform plan -var-file=prod.tfvars
```

```
  # module.storage.azurerm_storage_account.this will be updated in-place
  ~ resource "azurerm_storage_account" "this" {
      ~ allow_nested_items_to_be_public = true -> false
      ~ min_tls_version                 = "TLS1_0" -> "TLS1_2"
    }

Plan: 0 to add, 1 to change, 0 to destroy.
```

**Stop and look at that.** You did not change a single argument in your
configuration. You changed four characters in a URL, and your production storage
account's security posture changed. That is the entire argument for pinning:

- **Pinned**, this change happens when you decide, in a pull request somebody
  reviews, with the plan visible.
- **Unpinned**, it happens the next time anyone runs `init`, which might be a
  pipeline at 3am, applying a change nobody proposed.

This particular change is one you want. Take it:

```powershell
terraform apply -var-file=prod.tfvars
```

Now use the input v1.1.0 added. In `prod.tfvars`, production should not be
storing orders on single-datacenter redundancy:

```hcl
storage_replication_type = "ZRS"
```

Add the variable to `environments/prod/variables.tf`:

```hcl
variable "storage_replication_type" {
  description = "Redundancy for the production storage account."
  type        = string
  default     = "LRS"
}
```

And pass it in the module block:

```hcl
module "storage" {
  source = "git::.../storage?ref=v1.1.0"
  ...
  replication_type = var.storage_replication_type
}
```

```powershell
terraform plan -var-file=prod.tfvars
```

`~ account_replication_type = "LRS" -> "ZRS"`, updated in place. Apply it.

> That input **did not exist** in v1.0.0. If you try to pass it with the old pin
> you get `An argument named "replication_type" is not expected here`. Module
> version and module inputs move together, which is why the plan and the pin
> belong in the same pull request.

## Part 8: Being a good consumer

You will hit something a module does not do. The rule at Summit:

| Situation | What to do |
|---|---|
| The module has an input for it | Use it |
| The module is missing an input you need | Open an issue on `az-tf-ops-modules` with your use case |
| You need it before the platform team can ship it | Talk to them. A temporary resource in your own configuration, with a comment linking the issue, is acceptable. A forked module is not |
| The module has a bug | Issue, with your inputs and the plan output |
| You want a new module | Issue. Somebody else probably wants it too |

The reason forking is banned is not territorial. A forked module stops receiving
security fixes like the v1.1.0 TLS change, and nobody notices for a year.

**Practice it.** Open an issue on the modules repository asking for something the
`network` module cannot do today. Read `network/variables.tf` again and find a
real gap: per-subnet NSGs, outbound rules, service endpoints, delegation. Write
two or three sentences: what you are trying to do, what you tried, and what
input would solve it.

<!-- screenshot: a well-written module issue on GitHub -> images/module-issue.png -->

## Part 9: Commit

```powershell
cd C:\labs\az-tf-ops-<your-username>
terraform -chdir=environments/prod fmt

git add -A
git status
git commit -m "Build prod from shared modules, pin storage to v1.1.0"
git push -u origin feature/lab07-prod-from-modules
```

Note that `.terraform/modules/` is not in the commit: it is a cache, rebuilt by
`init`.

Open a pull request. In the description, do what a real reviewer needs: say
which module versions you pinned and paste the plan summary. Merge, then pull
`main`.

## How to verify

- [ ] `terraform plan -var-file=prod.tfvars` in prod reports **No changes**
- [ ] `terraform state list` in prod shows addresses beginning `module.`
- [ ] `rg-summit-orders-prod` in the portal has a VNet with two subnets, a VM, and a storage account
- [ ] The prod storage account shows **Minimum TLS version: 1.2** and **Redundancy: ZRS**
- [ ] Dev is untouched: `terraform plan -var-file=dev.tfvars` in dev still reports **No changes**
- [ ] You opened an issue on the modules repository

## If you get stuck

| Error | What it means and what to do |
|---|---|
| `Module not found` / `could not download module` | Check the `//` before the subdirectory, and that the tag exists. Test with `git ls-remote --tags https://github.com/Innovation-In-Software/az-tf-ops-modules.git`. |
| `Unsupported argument` on a module block | You passed an input the module does not have at that version. Read `variables.tf` **at that tag**, not on `main`. |
| `Missing required argument` on a module block | An input with no default was not supplied. The error names it. |
| `Invalid index` on `module.network.subnet_ids["app"]` | Your `subnets` map does not have an `app` key. The key you define is the key you look up. |
| Plan wants to replace prod resources after a pin bump | Read which attribute forces replacement. Not every version bump is in-place; that is what the plan is for. |
| `terraform plan` still uses the old module version | Module changes need `terraform init -upgrade`. Plain `init` keeps the cached copy. |
| `Computed storage account name ... is longer than 24 characters` | The storage module's precondition caught it. Shorten your suffix. |
| Git asks for credentials on `init` | You typed `git::ssh://` instead of `git::https://`, or the URL has a typo. The repository is public; HTTPS needs no credentials. |

## Cleanup

Keep both environments. Deallocate both VMs at the end of the day:

```powershell
az vm deallocate -g rg-summit-orders-dev  -n vm-summit-orders-dev
az vm deallocate -g rg-summit-orders-prod -n vm-summit-orders-prod
```

## Congratulations!

You built a complete production environment out of modules somebody else
maintains, wired their outputs together, and watched a version pin turn a
supply-chain risk into a reviewed decision.

Both environments now have one thing left in common that should worry you: the
VM admin password is passed in as a variable, which means it lives in somebody's
shell, somebody's history, and definitely in state. Lab 8 takes it out of your
hands entirely.
