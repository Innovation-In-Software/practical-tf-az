# Lab 9: Importing Existing Azure Infrastructure

## Overview

Everything you have built this week was Greenfield: new resources, created by
Terraform, tracked from birth. That is the easy half of the job.

The other half is `rg-legacy-reporting`. Somebody built it in the portal three
years ago. They have left. It holds the finance reporting extracts, it is
load-bearing, and nobody is allowed to delete and rebuild it to make your
Terraform tidy. You have to bring it under management **as it is**.

This is **Brownfield** work, and it is most of what an established operations
team actually does with Terraform.

The workflow, and the one sentence that saves you an afternoon:

> **`import` puts a resource into state. It does not write your configuration.**
> You still have to produce HCL that matches reality, and reality is going to
> surprise you.

You will use the modern approach: `import` blocks, which are reviewable in a
pull request, plus `-generate-config-out` to draft the configuration for you.

## Objectives

By the end of this lab you can:

- Decide what is worth importing and what is not
- Find an Azure resource ID from the portal and from the CLI
- Write `import` blocks and explain how they differ from `terraform import`
- Generate a draft configuration with `terraform plan -generate-config-out`
- Clean up generated configuration and reconcile it until `plan` is clean
- Explain what "successfully imported" means and how you prove it

## What you'll need

- Your repository with Lab 8 merged
- `az login` current, `ARM_SUBSCRIPTION_ID` set, your suffix

```powershell
cd C:\labs\az-tf-ops-<your-username>
git switch main
git pull
git switch -c feature/lab09-import-legacy-reporting
```

## Part 1: Meet the legacy environment

Create it (in a real engagement it would already be there):

```powershell
.\scripts\seed-legacy-reporting.ps1 -Suffix <suffix>
```

Now look at what you inherited:

```powershell
az resource list --resource-group rg-legacy-reporting --query "[].{name:name, type:type}" -o table
az group show --name rg-legacy-reporting --query tags
```

```
{
  "CostCentre": "FIN-2019",
  "Owner": "dave.reporting",
  "env": "Production"
}
```

Look at those tag keys. `Owner` with a capital O, `CostCentre` in British
spelling, `env` instead of `environment`. Summit's standard is
`environment` / `solution` / `owner` / `managed_by`, all lowercase. Nothing here
matches, because there was no standard when this was built.

Open `rg-legacy-reporting` in the portal too. Click through the storage account's
**Configuration** blade and note **Minimum TLS version: Version 1.0** and
**Access tier: Cool**. Nobody chose those on purpose; they were defaults, or the
defaults of the day.

**Write down what you find before you write any HCL.** Every one of these
details will show up in a plan later, and knowing which are real makes the
difference between a twenty-minute lab and a two-hour one.

### What to import, and what to leave

You will not import everything in an estate, and trying to is how these projects
stall. A workable rule:

| Import it | Leave it |
|---|---|
| Load-bearing and long-lived | Genuinely disposable |
| You will need to change it | Nobody has touched it in two years and nobody will |
| It has to be rebuilt for DR | Owned by another team |
| It is in scope for compliance | Slated for deletion |

For this lab, all five resources are in scope: the resource group, the storage
account and its container, the virtual network and its subnet.

## Part 2: Give it a home in the repository

Legacy reporting is not dev and it is not prod. It gets its own root module and
its own state file, following the same pattern as everything else.

```powershell
mkdir environments\legacy-reporting
cd environments\legacy-reporting
```

Create `backend.tf`:

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-summit-tfstate"
    storage_account_name = "stsummittfstate<suffix>"
    container_name       = "tfstate"
    key                  = "orders-legacy.terraform.tfstate"
  }
}
```

Create `main.tf` with nothing but the plumbing:

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
```

```powershell
terraform init
```

> Importing into a **separate state file** is deliberate. A first import attempt
> can go sideways, and you want the blast radius of "I got this wrong" to be a
> state file that contains nothing else.

## Part 3: Find the resource IDs

Terraform identifies an Azure resource by its full resource ID. The seed script
printed them, but you will not have a script in real life, so learn both ways to
find one.

**From the CLI**, which is how you will actually do it:

```powershell
az group show --name rg-legacy-reporting --query id -o tsv

az storage account show `
  --name stsmtlegacy<suffix> `
  --resource-group rg-legacy-reporting `
  --query id -o tsv

az network vnet show `
  --name legacy-reporting-vnet `
  --resource-group rg-legacy-reporting `
  --query id -o tsv

az network vnet subnet show `
  --name default `
  --vnet-name legacy-reporting-vnet `
  --resource-group rg-legacy-reporting `
  --query id -o tsv
```

**From the portal**: open any resource, then **Settings** > **Properties**, or
**JSON View** in the top right of the Overview blade. The `id` field is at the
top.

<!-- screenshot: Azure portal JSON View showing a resource id -> images/portal-resource-id.png -->

### The ID format

```
/subscriptions/<subscription id>/resourceGroups/rg-legacy-reporting/providers/Microsoft.Storage/storageAccounts/stsmtlegacyjr42
 ^^^^^^^^^^^^^ ^^^^^^^^^^^^^^^^^ ^^^^^^^^^^^^^^ ^^^^^^^^^^^^^^^^^^^ ^^^^^^^^^ ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ ^^^^^^^^^^^^^^^^
 always        yours              always         the group           always    provider/type                 the name
```

Nested resources extend the path. A blob container hangs off its storage
account:

```
<storage account id>/blobServices/default/containers/reports
```

and a subnet hangs off its virtual network:

```
<vnet id>/subnets/default
```

Two gotchas:

- **Case matters** in the parts Azure assigned. Copy IDs, do not retype them.
- **`resourceGroups` is camelCase** in the path even though the CLI flag is
  `--resource-group`. Copying beats typing.

## Part 4: Write the import blocks

An `import` block says "the resource at this Terraform address already exists in
Azure, at this ID."

Create `environments/legacy-reporting/imports.tf`. Substitute your subscription
id and suffix, or better, paste the IDs the script printed:

```hcl
import {
  to = azurerm_resource_group.legacy
  id = "/subscriptions/<sub-id>/resourceGroups/rg-legacy-reporting"
}

import {
  to = azurerm_storage_account.reports
  id = "/subscriptions/<sub-id>/resourceGroups/rg-legacy-reporting/providers/Microsoft.Storage/storageAccounts/stsmtlegacy<suffix>"
}

import {
  to = azurerm_storage_container.reports
  id = "/subscriptions/<sub-id>/resourceGroups/rg-legacy-reporting/providers/Microsoft.Storage/storageAccounts/stsmtlegacy<suffix>/blobServices/default/containers/reports"
}

import {
  to = azurerm_virtual_network.legacy
  id = "/subscriptions/<sub-id>/resourceGroups/rg-legacy-reporting/providers/Microsoft.Network/virtualNetworks/legacy-reporting-vnet"
}

import {
  to = azurerm_subnet.default
  id = "/subscriptions/<sub-id>/resourceGroups/rg-legacy-reporting/providers/Microsoft.Network/virtualNetworks/legacy-reporting-vnet/subnets/default"
}
```

`to` is the Terraform address you want it to have from now on. You choose those
names. `id` is Azure's.

Tip for filling in the subscription id:

```powershell
az account show --query id -o tsv
```

### Why blocks and not the command

The older way is a CLI command, one resource at a time:

```powershell
terraform import azurerm_resource_group.legacy "/subscriptions/.../rg-legacy-reporting"
```

It still works, and you will see it in older documentation. Compare the two:

| | `terraform import` command | `import` block |
|---|---|---|
| Where it lives | somebody's terminal | a file in the repository |
| Reviewable in a pull request | no | yes |
| Previewable with `plan` | no, it acts immediately | yes |
| Works in a pipeline | awkwardly | naturally |
| Can generate config for you | no | yes, with `-generate-config-out` |
| Available since | always | Terraform 1.5 |

Use blocks. Keep the command for one-off repairs, the same way you kept
`state mv` from Lab 5.

## Part 5: Generate a draft configuration

Right now you have five `import` blocks pointing at resource addresses that do
not exist in any configuration. Terraform can write a first draft for you:

```powershell
terraform plan -generate-config-out=generated.tf
```

```
Terraform will perform the following actions:

  # azurerm_resource_group.legacy will be imported
  # azurerm_storage_account.reports will be imported
  ...

Plan: 5 to import, 0 to add, 0 to change, 0 to destroy.

Terraform has generated configuration and written it to generated.tf. Please
review the configuration and edit it as necessary before adding it to version
control.
```

Open `generated.tf`. It is long, it is ugly, and it is a starting point, not an
answer.

Read that warning literally. The generated file contains **every attribute the
provider knows about**, including read-only ones, defaults, and computed values.
It is a dump of reality, not a configuration a human would write.

## Part 6: Clean up the draft

This is the actual work of the lab, and it is the part no tool does for you.

Create `main.tf` content by moving the good parts out of `generated.tf`. For each
resource, keep the arguments that are **real decisions** and delete the rest.

Keep:

- required arguments (`name`, `location`, `resource_group_name`)
- anything that differs from the provider default
- anything you would want to control going forward, such as tags

Delete:

- `id` and anything marked read-only. These are outputs, not inputs
- arguments the generator emitted at their default value
- empty blocks such as `blob_properties {}` or `identity {}` with nothing in
  them
- `null` values

Here is what a cleaned-up version looks like. Add this to
`environments/legacy-reporting/main.tf`:

```hcl
resource "azurerm_resource_group" "legacy" {
  name     = "rg-legacy-reporting"
  location = "eastus"

  # Reality, not Summit's standard. Reconciling these is a separate,
  # reviewed change: see the note at the end of this lab.
  tags = {
    Owner      = "dave.reporting"
    CostCentre = "FIN-2019"
    env        = "Production"
  }
}

resource "azurerm_storage_account" "reports" {
  name                     = "stsmtlegacy<suffix>"
  resource_group_name      = azurerm_resource_group.legacy.name
  location                 = azurerm_resource_group.legacy.location
  account_tier             = "Standard"
  account_replication_type = "GRS"
  account_kind             = "StorageV2"
  access_tier              = "Cool"

  # Genuinely how it is configured today. Do not "fix" it here: see below.
  min_tls_version = "TLS1_0"

  tags = {
    Owner = "dave.reporting"
    env   = "Production"
  }
}

resource "azurerm_storage_container" "reports" {
  name                  = "reports"
  storage_account_id    = azurerm_storage_account.reports.id
  container_access_type = "private"
}

resource "azurerm_virtual_network" "legacy" {
  name                = "legacy-reporting-vnet"
  resource_group_name = azurerm_resource_group.legacy.name
  location            = azurerm_resource_group.legacy.location
  address_space       = ["172.16.0.0/16"]

  tags = {
    Owner = "dave.reporting"
  }
}

resource "azurerm_subnet" "default" {
  name                 = "default"
  resource_group_name  = azurerm_resource_group.legacy.name
  virtual_network_name = azurerm_virtual_network.legacy.name
  address_prefixes     = ["172.16.10.0/24"]
}
```

Notice the improvement over the generated draft: the storage account references
`azurerm_resource_group.legacy.name` instead of repeating the literal. The
generator cannot know that two resources are related; you can.

Now delete the draft, because it must not be committed:

```powershell
Remove-Item generated.tf
```

(It is gitignored anyway. Deleting it stops you confusing yourself later.)

> **The single most important rule in this lab.** You just wrote
> `min_tls_version = "TLS1_0"` into a configuration, knowing it is wrong. Do it
> anyway. Import means "describe what is there." If you improve things in the
> same change, you cannot tell an import mistake from an intentional
> improvement, and your first `apply` becomes a change to production you did not
> plan. **Import first, get to a clean plan, commit. Improve second, as its own
> pull request.**

## Part 7: Run the import

```powershell
terraform plan
```

You want:

```
Plan: 5 to import, 0 to add, 0 to change, 0 to destroy.
```

**`0 to change` is the number that matters.** If it is anything else, your
configuration does not match reality yet. Go to Part 8, then come back.

```powershell
terraform apply
```

```
Apply complete! Resources: 5 imported, 0 added, 0 changed, 0 destroyed.
```

Prove it:

```powershell
terraform state list
```

```
azurerm_resource_group.legacy
azurerm_storage_account.reports
azurerm_storage_container.reports
azurerm_subnet.default
azurerm_virtual_network.legacy
```

```powershell
terraform plan
```

**No changes. Your infrastructure matches the configuration.**

That sentence, on resources you did not create, is the definition of a
successful import. Nothing was destroyed, nothing was rebuilt, and the finance
team never noticed.

## Part 8: Reconciling a plan that is not clean

Almost nobody gets `0 to change` on the first try. Here is the method.

Read each proposed change and ask: **is the configuration wrong, or is reality
wrong?**

Nine times out of ten during an import, the configuration is wrong: you guessed
an attribute the generator did not emit, or you tidied something on the way past.

| Plan says | Usually means | Do this |
|---|---|---|
| `~ min_tls_version = "TLS1_0" -> "TLS1_2"` | You "fixed" it while cleaning up | Put the real value back. Improve it in a later pull request |
| `~ tags = { - Owner = "dave.reporting" }` | You dropped a tag you did not like | Put it back. Import describes what is |
| `~ access_tier = "Cool" -> "Hot"` | You deleted a non-default argument, so the provider default applies | Add the real value back |
| `-/+ must be replaced` | A name, region, or other immutable attribute does not match | **Stop.** Do not apply. Fix the configuration |
| `- will be destroyed` | You have an `import` block with no matching `resource` block, or an address typo | Match the addresses |
| `+ will be created` | Same problem, the other way round: a `resource` block whose ID you did not import | Check the `import` block ID |

To find the truth about any attribute:

```powershell
az storage account show --name stsmtlegacy<suffix> --resource-group rg-legacy-reporting
```

Or, once the resource is in state:

```powershell
terraform state show azurerm_storage_account.reports
```

Iterate: edit, `plan`, read, edit. Two or three rounds is normal on real
resources with fifty attributes.

> **Never respond to an unwanted change by applying it.** A plan during an import
> that says "1 to change" is Terraform telling you it is about to modify
> production to match a file you wrote from a guess.

## Part 9: Deliberately break one, so you have seen it

Worth doing once in a lab rather than for the first time in an incident.

1. In `main.tf`, change the storage account's `access_tier` from `"Cool"` to
   `"Hot"`.
2. `terraform plan`

```
  ~ resource "azurerm_storage_account" "reports" {
      ~ access_tier = "Cool" -> "Hot"
    }

Plan: 0 to add, 1 to change, 0 to destroy.
```

That is a real change to a real storage account, with a real cost impact,
proposed because of a one-word edit. Nothing warned you beyond this line.

3. Put `"Cool"` back and confirm `terraform plan` says **No changes**.

Now try one that is worse:

4. Change the resource group's `location` from `"eastus"` to `"westus"`.
5. `terraform plan`

```
  # azurerm_resource_group.legacy must be replaced
-/+ resource "azurerm_resource_group" "legacy" {
      ~ location = "eastus" -> "westus" # forces replacement
    }
```

Replacing a resource group means **deleting it and everything inside it**. This
is the plan you have to be able to spot at 5pm on a Friday.

6. Put `"eastus"` back. Confirm **No changes**.

## Part 10: Commit, then improve separately

First, commit the import exactly as it is:

```powershell
cd C:\labs\az-tf-ops-<your-username>
terraform -chdir=environments/legacy-reporting fmt

git add -A
git status
```

Confirm `generated.tf` is **not** in the list.

```powershell
git commit -m "Import rg-legacy-reporting under Terraform management, no changes"
git push -u origin feature/lab09-import-legacy-reporting
```

Open a pull request. Title it so a reviewer knows the risk profile:
`Import legacy reporting (no infrastructure changes)`. In the description, paste
the plan summary: `5 to import, 0 to add, 0 to change, 0 to destroy`. That line
is what lets a reviewer approve quickly and confidently.

Merge, pull `main`.

### Now the improvement, as its own change

The environment is under management, so you can finally fix it the way you fix
anything else: in code, in a pull request, with a plan a human reads.

```powershell
git switch -c fix/legacy-reporting-tls-and-tags
```

In `environments/legacy-reporting/main.tf`:

```hcl
resource "azurerm_storage_account" "reports" {
  ...
  min_tls_version = "TLS1_2"
  ...
  tags = {
    environment = "prod"
    solution    = "reporting"
    owner       = "ops-team"
    managed_by  = "terraform"
  }
}
```

Do the same for the resource group and virtual network tags.

```powershell
cd environments\legacy-reporting
terraform plan
```

```
Plan: 0 to add, 3 to change, 0 to destroy.
```

Three in-place updates, each one visible, each one intentional. Apply, commit,
and open a second pull request.

**Look at what just happened.** Two pull requests. The first was mechanically
verifiable ("nothing changed") and needed almost no review. The second contained
exactly the three changes under discussion, and a reviewer could see all of them
in ten seconds. If you had done both at once, the reviewer would have had to
check fifty attributes to find the three that mattered. That separation is the
whole discipline of Brownfield work.

## How to verify

- [ ] `terraform state list` in `environments/legacy-reporting` shows all 5 resources
- [ ] `terraform plan` reports **No changes**
- [ ] `az storage account show ... --query minimumTlsVersion` returns `TLS1_2`
- [ ] The resource group carries Summit's four standard tags
- [ ] Nothing in `rg-legacy-reporting` was recreated: check **Activity log** in
      the portal and confirm no delete operations
- [ ] Both pull requests are merged, and `generated.tf` is not in the repository

## If you get stuck

| Error | What it means and what to do |
|---|---|
| `Cannot import non-existent remote object` | The ID is wrong. Get it again with `az ... --query id -o tsv` and paste it rather than typing it. |
| `Resource already managed by Terraform` | It is already in this state file. `terraform state list` to confirm, then remove the `import` block. |
| `Configuration for import target does not exist` | You have an `import` block with no matching `resource` block at that address. |
| `-generate-config-out` refuses to run | The target file already exists. Delete `generated.tf` and rerun. |
| Generated config will not validate | Normal. It emits read-only attributes. Delete them; the error names each one. |
| Plan wants to **replace** an imported resource | An immutable attribute does not match. Do not apply. Compare with `terraform state show` or `az ... show`. |
| Plan wants to **destroy** something | An `import` block address does not match any `resource` block address. Check spelling on both. |
| Subnet import fails | Subnet IDs nest under the VNet: `<vnet id>/subnets/<name>`. |
| Container import fails | Container IDs nest under the storage account: `<sa id>/blobServices/default/containers/<name>`. |

## Challenge (optional)

Import the whole environment a second time, from scratch, using only the CLI:

```powershell
terraform state rm azurerm_storage_container.reports
terraform import azurerm_storage_container.reports "<the container id>"
```

Compare the experience with the `import` block. Notice there is no plan, no
preview, and no record in the repository that it happened.

## Cleanup

Keep everything: Lab 11 uses `rg-legacy-reporting` for the drift exercise.

## Congratulations!

You brought an undocumented, hand-built environment under Terraform management
without deleting a single resource, and then improved it as a separate,
reviewable change.

This is the capability that unblocks an existing estate. Greenfield Terraform is
a tutorial; being able to say "yes, we can manage what is already there, safely"
is what makes the tool worth adopting at Summit.

Lab 10 takes the whole repository and hands it to a pipeline.
