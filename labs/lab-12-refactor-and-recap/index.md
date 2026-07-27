# Lab 12: Refactoring with `moved`, and Proving It All Works

## Overview

One inconsistency has been sitting in Summit's repository since Tuesday.
`environments/prod` is sixty lines of module calls. `environments/dev` is a
hundred and thirty lines of hand-written resources, because you wrote it before
you knew modules existed.

That is not a cosmetic problem. Dev and prod are now built differently, so a
security fix the platform team ships to a module reaches prod and misses dev,
and every change has to be made twice in two shapes.

Fixing it means every resource in dev changes address: `azurerm_linux_virtual_machine.app`
becomes `module.app_vm.azurerm_linux_virtual_machine.this`. You learned in Lab 5
what Terraform does with an address change. It destroys and recreates. Doing that
to eleven resources including a running VM is not a refactor, it is an outage.

The tool for this is the **`moved` block**. This lab uses it to rebuild dev on
shared modules with **zero resources destroyed**, then proves the whole thing
works by tearing dev down and building it back from nothing.

## Objectives

By the end of this lab you can:

- Explain what a `moved` block does and how it differs from `terraform state mv`
- Refactor a configuration into modules without destroying anything
- Read a plan that contains moves and verify the destroy count is zero
- Prove an environment is reproducible by destroying and rebuilding it
- Tear down a Terraform estate in the right order

## What you'll need

- Your repository with Lab 11 merged
- Both VMs running (`az vm start` if you deallocated them)
- The usual environment variables

```powershell
cd C:\labs\az-tf-ops-<your-username>
git switch main
git pull
git switch -c feature/lab12-dev-on-modules

$env:TF_VAR_allowed_ssh_source = "$(Invoke-RestMethod https://api.ipify.org)/32"
cd environments\dev
terraform plan -var-file=dev.tfvars
```

Clean plan before you start.

## Part 1: See the problem first

Before writing any `moved` blocks, look at what happens without them.

Note what you have now:

```powershell
terraform state list
```

Eleven resources, all at top-level addresses.

Now, temporarily, add a single module call to `environments/dev/main.tf` for
the storage account, without removing the existing `azurerm_storage_account`
resource:

```hcl
module "storage" {
  source = "git::https://github.com/Innovation-In-Software/az-tf-ops-modules.git//storage?ref=v1.1.0"

  name_prefix         = local.name_prefix
  name_suffix         = var.storage_name_suffix
  resource_group_name = azurerm_resource_group.orders.name
  location            = var.location
  containers          = var.storage_containers
  tags                = local.tags
}
```

```powershell
terraform init
terraform plan -var-file=dev.tfvars
```

```
Error: A resource with the ID "/subscriptions/.../storageAccounts/stsummitordersdevjr42"
already exists - to be managed via Terraform this resource needs to be imported
into the State.
```

Terraform is trying to **create** a storage account at that address, because
`module.storage.azurerm_storage_account.this` is a new address it has never seen.
It has no idea that `azurerm_storage_account.orders` is the same account.

Now delete the old `azurerm_storage_account` and `azurerm_storage_container`
resource blocks, leaving only the module. Plan again:

```
Plan: 3 to add, 0 to change, 3 to destroy.
```

There it is. It will **delete your storage account and both containers** and
build new ones. Same name, same everything, and yet destroyed and recreated,
because Terraform tracks resources by address and the addresses changed.

On an empty container that is survivable. On the VM it would be a rebuild, and
on anything holding data it would be data loss.

**Do not apply.** Now fix it properly.

## Part 2: The `moved` block

```hcl
moved {
  from = azurerm_storage_account.orders
  to   = module.storage.azurerm_storage_account.this
}
```

That is it. It tells Terraform: the thing that used to live at this address now
lives at that one. It is the same real resource; update the state record and
leave Azure alone.

Add that block to `environments/dev/main.tf` and plan again:

```powershell
terraform plan -var-file=dev.tfvars
```

```
Terraform will perform the following actions:

  # azurerm_storage_account.orders has moved to module.storage.azurerm_storage_account.this
    resource "azurerm_storage_account" "this" {
        id = "/subscriptions/.../stsummitordersdevjr42"
        name = "stsummitordersdevjr42"
    }
```

No `+`, no `-`. Just "has moved to."

### `moved` versus `state mv`

In Lab 5 you did the same job with `terraform state mv`. Both work. They are not
equivalent.

| | `terraform state mv` | `moved` block |
|---|---|---|
| Where it lives | somebody's terminal | a file in the repository |
| Reviewable in a pull request | no | yes |
| Visible in `plan` before it happens | no | yes |
| Runs in a pipeline | no | yes, automatically |
| Applies for teammates | they never run it, but state is shared, so it is already done | yes, when they pull |
| Reversible | rerun it backwards, if you remember | revert the commit |
| Undo history | none | git log |

**The pipeline argument settles it.** Since Lab 10, nobody runs Terraform by
hand. A refactor that requires somebody to type a state command on their laptop
cannot be delivered by your pipeline at all. `moved` is a line of code, so it
travels through the pull request, the plan check shows it, the reviewer sees it,
and the merge applies it.

Use `moved` for anything you are committing. Keep `state mv` for interactive
repair.

> **`moved` blocks are safe to leave in place**, and Terraform ignores them once
> the move has happened. Convention is to keep them for a release or two, so a
> teammate on an older state still gets the move, then delete them in a tidy-up
> commit.

## Part 3: Refactor the whole environment

Now do all eleven. Replace the entire contents of `environments/dev/main.tf`
with this.

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
    cost_center = "retail-ops"
    ticket      = "INC-4471"
  }
}

# ---------------------------------------------------------------------------
# Secrets, unchanged from Lab 8.
# ---------------------------------------------------------------------------
data "azurerm_key_vault" "orders" {
  name                = var.key_vault_name
  resource_group_name = var.key_vault_resource_group_name
}

data "azurerm_key_vault_secret" "vm_admin_password" {
  name         = "vm-admin-password"
  key_vault_id = data.azurerm_key_vault.orders.id
}

# ---------------------------------------------------------------------------
# The resource group stays inline. A one-line resource does not earn a module.
# ---------------------------------------------------------------------------
resource "azurerm_resource_group" "orders" {
  name     = "rg-${local.name_prefix}"
  location = var.location
  tags     = local.tags
}

module "network" {
  source = "git::https://github.com/Innovation-In-Software/az-tf-ops-modules.git//network?ref=v1.1.0"

  name_prefix         = local.name_prefix
  resource_group_name = azurerm_resource_group.orders.name
  location            = var.location
  address_space       = var.vnet_address_space

  subnets = {
    app = { address_prefix = cidrsubnet(var.vnet_address_space[0], 8, 1) }
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

module "app_vm" {
  source = "git::https://github.com/Innovation-In-Software/az-tf-ops-modules.git//linux-vm?ref=v1.1.0"

  name_prefix         = local.name_prefix
  resource_group_name = azurerm_resource_group.orders.name
  location            = var.location
  subnet_id           = module.network.subnet_ids["app"]

  vm_size        = var.vm_size
  admin_username = var.vm_admin_username
  admin_password = data.azurerm_key_vault_secret.vm_admin_password.value

  tags = merge(local.tags, { role = "app-server" })
}

module "storage" {
  source = "git::https://github.com/Innovation-In-Software/az-tf-ops-modules.git//storage?ref=v1.1.0"

  name_prefix         = local.name_prefix
  name_suffix         = var.storage_name_suffix
  resource_group_name = azurerm_resource_group.orders.name
  location            = var.location
  containers          = var.storage_containers

  tags = local.tags
}
```

From a hundred and thirty lines to about ninety, and more importantly, dev and
prod are now the same shape.

### Now the moves

Create `environments/dev/moved.tf`. A separate file keeps the refactor visible
in the pull request and makes it easy to delete later.

```hcl
# ---------------------------------------------------------------------------
# Lab 12: dev was written as inline resources before Summit's shared modules
# existed. These blocks re-point the existing resources at their new addresses
# inside the modules. Nothing is created or destroyed.
#
# Safe to delete once every environment has applied this change.
# ---------------------------------------------------------------------------

moved {
  from = azurerm_virtual_network.orders
  to   = module.network.azurerm_virtual_network.this
}

moved {
  from = azurerm_subnet.app
  to   = module.network.azurerm_subnet.this["app"]
}

moved {
  from = azurerm_network_security_group.orders
  to   = module.network.azurerm_network_security_group.this
}

moved {
  from = azurerm_network_security_rule.ssh
  to   = module.network.azurerm_network_security_rule.inbound["AllowSSHFromAdmin"]
}

moved {
  from = azurerm_subnet_network_security_group_association.app
  to   = module.network.azurerm_subnet_network_security_group_association.this["app"]
}

moved {
  from = azurerm_public_ip.app
  to   = module.app_vm.azurerm_public_ip.this[0]
}

moved {
  from = azurerm_network_interface.app
  to   = module.app_vm.azurerm_network_interface.this
}

moved {
  from = azurerm_linux_virtual_machine.app
  to   = module.app_vm.azurerm_linux_virtual_machine.this
}

moved {
  from = azurerm_storage_account.orders
  to   = module.storage.azurerm_storage_account.this
}

moved {
  from = azurerm_storage_container.this["orders-data"]
  to   = module.storage.azurerm_storage_container.this["orders-data"]
}

moved {
  from = azurerm_storage_container.this["orders-logs"]
  to   = module.storage.azurerm_storage_container.this["orders-logs"]
}
```

Three address forms to notice:

| Form | Example | Why |
|---|---|---|
| Plain | `azurerm_virtual_network.orders` | a single resource |
| Map key | `azurerm_subnet.this["app"]` | inside a `for_each`, the key is part of the address |
| List index | `azurerm_public_ip.this[0]` | the module uses `count = var.create_public_ip ? 1 : 0`, so index `0` |

Get any of these wrong and Terraform plans a destroy. That is what the plan is
for.

### Update the outputs

`environments/dev/outputs.tf` still references resources that no longer exist at
those addresses. Replace it:

```hcl
output "resource_group_name" {
  description = "Name of the environment resource group."
  value       = azurerm_resource_group.orders.name
}

output "vm_public_ip" {
  description = "Public IP address of the application VM."
  value       = module.app_vm.public_ip_address
}

output "vm_ssh_command" {
  description = "Ready-to-paste SSH command."
  value       = module.app_vm.ssh_command
}

output "storage_account_name" {
  description = "Name of the environment storage account."
  value       = module.storage.storage_account_name
}

output "container_names" {
  description = "Blob containers created in this environment."
  value       = module.storage.container_names
}

output "subnet_ids" {
  description = "Map of subnet short name to resource ID."
  value       = module.network.subnet_ids
}
```

## Part 4: The plan that proves it

```powershell
terraform init
terraform fmt
terraform validate
terraform plan -var-file=dev.tfvars
```

**Read every line of this one.**

```
Terraform will perform the following actions:

  # azurerm_linux_virtual_machine.app has moved to module.app_vm.azurerm_linux_virtual_machine.this
  # azurerm_network_interface.app has moved to module.app_vm.azurerm_network_interface.this
  # azurerm_network_security_group.orders has moved to module.network.azurerm_network_security_group.this
  ... (eleven of these)

  # module.app_vm.azurerm_network_interface.this will be updated in-place
  ~ resource "azurerm_network_interface" "this" {
      ~ tags = {
          + "role" = "app-server"
        }
    }

  # module.storage.azurerm_storage_account.this will be updated in-place
  ~ resource "azurerm_storage_account" "this" {
      ~ allow_nested_items_to_be_public = true -> false
    }

Plan: 0 to add, 3 to change, 0 to destroy.
```

**`0 to add, 0 to destroy`** is the number this whole lab exists to produce.
Eleven resources changed address, including a running virtual machine, and not
one of them is being touched in Azure.

The three in-place changes are real and worth understanding rather than
ignoring:

| Change | Why |
|---|---|
| `allow_nested_items_to_be_public: true -> false` | The storage module's v1.1.0 security baseline. Dev never had it; now it does. This is exactly the "a module fix reaches prod and misses dev" problem, fixing itself. |
| `role = "app-server"` tag on the NIC | The module applies one tag set to all three of its resources. Previously only the VM carried the role tag. |
| `role = "app-server"` tag on the public IP | Same reason. |

> **If your plan shows anything to destroy, stop.** A `moved` block address is
> wrong. Find the resource being destroyed, compare its old address in
> `terraform state list` with the `from` in your `moved` block, character by
> character. Map keys and list indexes are the usual culprits.

```powershell
terraform apply -var-file=dev.tfvars
```

```
Apply complete! Resources: 0 added, 3 changed, 0 destroyed.
```

Confirm the addresses moved:

```powershell
terraform state list
```

```
azurerm_resource_group.orders
module.app_vm.azurerm_linux_virtual_machine.this
module.app_vm.azurerm_network_interface.this
module.app_vm.azurerm_public_ip.this[0]
module.network.azurerm_network_security_group.this
module.network.azurerm_network_security_rule.inbound["AllowSSHFromAdmin"]
module.network.azurerm_subnet.this["app"]
module.network.azurerm_subnet_network_security_group_association.this["app"]
module.network.azurerm_virtual_network.this
module.storage.azurerm_storage_account.this
module.storage.azurerm_storage_container.this["orders-data"]
module.storage.azurerm_storage_container.this["orders-logs"]
```

And confirm the VM never went anywhere:

```powershell
terraform output vm_ssh_command
ssh azureuser@<the IP>
```

Same machine, same IP, same uptime. Check it:

```
uptime
```

It has been up since Lab 8. **Eleven resources were re-homed into modules
underneath a running server and it did not notice.**

## Part 5: Ship it through the pipeline

```powershell
cd C:\labs\az-tf-ops-<your-username>
terraform -chdir=environments/dev fmt

git add -A
git commit -m "Refactor dev onto shared modules using moved blocks

Dev was written as inline resources before the shared modules existed, so a
module fix reached prod and missed dev. This moves all eleven resources into
module.network, module.app_vm, and module.storage.

Plan: 0 to add, 3 to change, 0 to destroy. The three changes are the storage
module's v1.1.0 security baseline and two tag additions."

git push -u origin feature/lab12-dev-on-modules
```

Open a pull request. Look at the plan comment your pipeline posted: a reviewer
can see eleven `has moved to` lines and `0 to destroy` without running anything.
**That is the argument for `moved` in one screenshot.**

Get it reviewed and merge it. The apply job runs on `main`, sees the moves are
already recorded in state from your local apply, and reports no changes. That is
correct: state is shared, so the work was already done.

```powershell
git switch main
git pull
```

## Part 6: Prove the whole thing works

Everything this week has been about one claim: infrastructure as code means an
environment is reproducible. Time to test it rather than assert it.

```powershell
cd environments\dev
terraform destroy -var-file=dev.tfvars
```

Read the plan first, then type `yes`. It takes a few minutes.

Dev is now gone. Check the portal: `rg-summit-orders-dev` no longer exists.

Now bring it back:

```powershell
terraform apply -var-file=dev.tfvars
```

```
Apply complete! Resources: 12 added, 0 changed, 0 destroyed.

Outputs:

storage_account_name = "stsummitordersdevjr42"
vm_ssh_command = "ssh azureuser@20.121.55.181"
```

A complete environment, from nothing, in about four minutes, with no clicks and
no decisions. The public IP is different because Azure allocated a new one;
everything else is identical, including tags, NSG rules, storage settings, and
the admin password, which came from the vault without anybody typing it.

Compare that with Lab 1, where you clicked through five screens to make a
resource group and a storage account and had no record of the defaults you
accepted.

```powershell
terraform plan -var-file=dev.tfvars
```

**No changes. Your infrastructure matches the configuration.**

## Part 7: The whole picture

Take two minutes and look at what the repository has become.

```
az-tf-ops-<your-username>/
  .github/workflows/
    terraform.yml                  Lab 10: plan on PR, apply on merge
  environments/
    dev/                           Labs 3-8, 12: modules, Key Vault, remote state
      main.tf  variables.tf  outputs.tf  moved.tf  backend.tf  dev.tfvars
    prod/                          Lab 7: built from modules from the start
      main.tf  variables.tf  outputs.tf  backend.tf  prod.tfvars
    legacy-reporting/              Lab 9: imported, not created
      main.tf  imports.tf  backend.tf
  scripts/                         bootstrap: backend, vaults, legacy, SP
  docs/
  README.md
```

and, outside it:

| Where | What |
|---|---|
| `az-tf-ops-modules` | Shared modules, pinned by tag, owned by another team |
| `rg-summit-tfstate` | Three state files, versioned, locked, access-controlled |
| `rg-summit-security` | Two Key Vaults holding credentials that are in no file |
| GitHub Actions secrets | The service principal the pipeline authenticates with |
| Branch protection on `main` | Review plus a passing plan, enforced |

Map that back to where Summit started on Monday morning: a resource group
somebody clicked into existence, and no way to answer "can you rebuild this
exactly?"

| Then | Now |
|---|---|
| Clicked in the portal | Declared in code |
| Undocumented defaults | Every value visible and reviewed |
| No history | Every change a commit, with an author and a reason |
| No review | Merge blocked without approval and a clean plan |
| State on a laptop | Shared, locked, versioned in Azure Storage |
| Environments drift apart | Same modules, different `.tfvars` |
| Passwords in shell history | Read from Key Vault at apply time |
| Legacy estate unmanageable | Imported, no downtime |
| Applied by whoever was around | Applied by a pipeline, on merge |
| "Can you rebuild this?" | You just did, in four minutes |

## Part 8: Tear it all down

Unless your instructor says otherwise, remove everything so nothing bills over
the weekend.

Order matters, and it is not obvious:

1. **Environments first** (`dev`, `prod`, `legacy-reporting`). They read
   credentials from the vaults and their state from the backend, so both have to
   still exist.
2. **Then the vaults**, with a purge. Key Vault soft delete keeps the name
   reserved for seven days otherwise.
3. **Then the state backend**, last, because steps 1 and 2 needed it.
4. **Then the service principal.**

Preview it:

```powershell
cd C:\labs\az-tf-ops-<your-username>
.\scripts\destroy-all.ps1 -Suffix <suffix> -WhatIf
```

Then run it:

```powershell
.\scripts\destroy-all.ps1 -Suffix <suffix>
```

Or do it by hand, which is worth doing once so the order sticks:

```powershell
cd environments\dev
terraform destroy -auto-approve -var-file=dev.tfvars

cd ..\prod
terraform destroy -auto-approve -var-file=prod.tfvars

cd ..\legacy-reporting
terraform destroy -auto-approve

az keyvault delete --name kv-summit-dev-<suffix>  --resource-group rg-summit-security
az keyvault delete --name kv-summit-prod-<suffix> --resource-group rg-summit-security
az keyvault purge  --name kv-summit-dev-<suffix>  --location eastus
az keyvault purge  --name kv-summit-prod-<suffix> --location eastus
az group delete --name rg-summit-security --yes --no-wait

az group delete --name rg-summit-tfstate --yes --no-wait
```

Confirm:

```powershell
az group list --query "[].name" -o table
```

Nothing beginning `rg-summit-` or `rg-legacy-` should remain. If something does,
delete it in the portal.

> **Keep the repository.** It is the most useful thing you take away from this
> week: a working, complete example of every pattern, in your own GitHub
> account, that you can copy into real work on Monday.

## How to verify

- [ ] `terraform state list` in dev shows every address prefixed `module.`, except the resource group
- [ ] The apply that moved them reported `0 destroyed`
- [ ] The VM's `uptime` showed it survived the refactor
- [ ] Destroying and rebuilding dev produced an identical environment
- [ ] The pull request's plan comment showed the moves and `0 to destroy`
- [ ] `az group list` shows no lab resource groups left

## If you get stuck

| Symptom | What to do |
|---|---|
| Plan shows resources being destroyed and recreated | A `moved` block `from` address does not match state exactly. Compare against `terraform state list`. |
| `Moved object still exists` | You wrote the `moved` block but left the old `resource` block in the file. Delete the old block. |
| `Unexpected \| Reference to undeclared module` | The `to` address names a module call that does not exist. The name after `module.` is your module block's label. |
| `A resource with the ID ... already exists` | The `moved` block is missing for that resource, so Terraform is trying to create it. |
| `Invalid index` on `azurerm_public_ip.this[0]` | The `linux-vm` module uses `count`, so the index is `[0]`, not `["app"]`. |
| Plan wants to replace the VM | Something other than the address changed too, usually `admin_username` or the image. Compare your module inputs with the old inline arguments. |
| `terraform destroy` fails on the Key Vault data source | You deleted the vaults before destroying the environments. Recreate the vault, or `terraform state rm` the affected resources and delete the resource group in the portal. |
| The pipeline's apply reports no changes after merge | Correct. Your local apply already moved them, and state is shared. |

## Congratulations!

You just did the hardest thing in this course: restructured a live environment
from top to bottom, under a running server, with nothing destroyed, and shipped
it through a pipeline where a reviewer could verify the claim before it merged.

Then you destroyed the environment and rebuilt it from a file, which is the
promise infrastructure as code makes and the one worth proving to a sceptical
colleague.

## Where to go next

**Greenfield.** Everything new at Summit starts as a directory under
`environments/`, built from the shared modules, with a backend key and a
pipeline. You have the template.

**Brownfield.** Pick one existing environment. Import it into its own state
file, get to a clean plan, and commit it with no changes. Then improve it. One
environment at a time is how an estate gets under control; a big-bang import
project is how it stalls.

**Things worth learning next, roughly in order:**

| Topic | Why |
|---|---|
| OIDC workload identity federation | Removes the last stored credential from your pipeline |
| Policy as code (Checkov, tfsec, Conftest) | A pipeline step that fails on a public storage account before a human has to notice |
| `terraform test` and Terratest | Modules deserve tests, especially ones other teams consume |
| Azure Policy alongside Terraform | Catches drift in what Terraform does **not** manage, the gap you found in Lab 11 |
| Scheduled drift detection | The optional challenge from Lab 11. Cheap, and it pays for itself the first time |
| Writing modules, not just consuming them | You are ready. You have read three good ones closely |

**A short list of habits worth keeping:**

- Read the plan. Every time. Especially when you are in a hurry
- Pin everything: Terraform version, provider version, module version
- Remote state, always. Never on a laptop
- No secrets in code, and check your history, not just your working directory
- Small pull requests. A reviewer who can read a plan in ten seconds will
- Import first, improve second, in separate pull requests
- `moved` for anything you commit, `state mv` only for interactive repair
- When something breaks, work out which layer it came from before you edit
  anything

That is the course. You started the week clicking through the Azure portal and
finished it delivering reviewed, version-controlled, pipeline-applied
infrastructure across three environments, including one you inherited rather
than built.

Nicely done.
