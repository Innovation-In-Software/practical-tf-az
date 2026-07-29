# Lab 5: Remote State and a Multi-Environment Repository

## Overview

Right now, Summit's entire Orders development environment depends on one file on
one laptop. If you lose `terraform.tfstate`, Terraform forgets that eleven
Azure resources exist and cheerfully offers to build them again. If a teammate clones
your repository and runs `apply`, they have no state at all and will try to
create resources that already exist. And if two of you run `apply` at the same
moment, there is nothing to stop you.

This lab fixes both problems at once:

1. **Move state into Azure Storage**, where it is shared, durable, and locked
   while somebody is applying.
2. **Restructure the repository** into the layout HashiCorp recommends for
   multiple environments, so `dev` and `prod` have separate configurations,
   separate backends, and separate state. A mistake in `dev` cannot reach `prod`
   because they do not share a state file.

By the end you have a repository shaped the way it will stay for the rest of the
week, and two state files in Azure instead of one on a disk.

## Objectives

By the end of this lab you can:

- Create an Azure Storage backend for Terraform state
- Configure `backend "azurerm"` and migrate existing local state into it
- Explain what state locking prevents and how the azurerm backend does it
- Lay out a repository with one directory and one state file per environment
- Inspect state with `state list` and `state show`
- Rename a resource without destroying it, using `terraform state mv`
- Explain when `terraform state rm` is the right tool and how to check yourself

## What you'll need

- Your repository, with Lab 4 applied and merged to `main`
- `ARM_SUBSCRIPTION_ID` set, and `az login` current
- Your 4-character student suffix

### Start clean

Get onto `main`, pull, then branch. All of this is in VS Code.

1. Open your repository in VS Code: **File > Open Recent**, then
   `az-tf-ops-<your-username>`.
2. Click the branch name in the bottom left status bar and choose `main`.
3. Click the sync icon (the circular arrows) next to it to pull.
4. Click the branch name again, choose **Create new branch...**, and name it:

   ```
   feature/lab05-remote-state
   ```

5. Confirm the status bar now shows `feature/lab05-remote-state`.

The command line equivalent:

```powershell
cd C:\Users\Administrator\Downloads\terraform\labs\az-tf-ops-<your-username>
git switch main
git pull
git switch -c feature/lab05-remote-state
```

### Confirm the last lab is still good

Terraform has no VS Code equivalent, so open a terminal with ``Ctrl+` ``:

```powershell
terraform plan
```

**Stop if that plan is not clean.** Migrating state is the wrong time to
discover you had pending changes.

Set your two variables again if this is a new terminal:

```powershell
$env:TF_VAR_allowed_ssh_source = "$(Invoke-RestMethod https://api.ipify.org)/32"
$env:TF_VAR_vm_admin_password = "Summit-Lab-2026!"
```

## Part 1: Build the backend storage

The state backend is a chicken-and-egg problem: Terraform needs somewhere to
keep state, and that somewhere cannot itself be managed by the state you have
not created yet. Every team solves it the same way, by creating the backend once
with a script and then leaving it alone.

Run these four commands. Replace `<suffix>` with yours.

```powershell
az group create `
  --name rg-summit-tfstate `
  --location eastus `
  --tags solution=orders owner=ops-team managed_by=bootstrap

az storage account create `
  --name stsummittfstate<suffix> `
  --resource-group rg-summit-tfstate `
  --location eastus `
  --sku Standard_LRS `
  --kind StorageV2 `
  --min-tls-version TLS1_2 `
  --allow-blob-public-access false

az storage account blob-service-properties update `
  --account-name stsummittfstate<suffix> `
  --resource-group rg-summit-tfstate `
  --enable-versioning true

az storage container create `
  --name tfstate `
  --account-name stsummittfstate<suffix> `
  --auth-mode login
```

(The backtick is PowerShell's line continuation. On macOS or Linux use a
backslash, or put each command on one line.)

There is a ready-made version of this in the repository at
`scripts/bootstrap-backend.ps1` if you would rather run it than type it.

Three deliberate choices in there:

- **A separate resource group.** `rg-summit-tfstate` is not part of any
  environment. If someone destroys `dev`, the state survives.
- **Blob versioning on.** Every state write keeps the previous version. This is
  the cheapest insurance you will ever buy, and it has saved more Terraform
  users than any other single setting.
- **Public blob access off.** State contains, among other things, your VM
  password in plain text.

Confirm it exists:

```powershell
az storage container list --account-name stsummittfstate<suffix> --auth-mode login -o table
```

## Part 2: Restructure the repository

Your files are at the repository root, which works for exactly one environment.
The layout you want is one directory per environment:

```
az-tf-ops-<your-username>/
  environments/
    dev/
      main.tf
      variables.tf
      outputs.tf
      backend.tf
    prod/
      main.tf
      variables.tf
      backend.tf
  scripts/
  docs/
  README.md
```

Each directory is its own **root module**: its own `terraform init`, its own
backend, its own state, its own `plan` and `apply`. They share nothing except
the modules they call.

Move your existing configuration into `environments/dev`. Do this in the VS Code
**Explorer**:

1. Hover over the repository name at the top of the Explorer and click the
   **New Folder...** icon. Name it `environments`.
2. Right-click `environments` and choose **New Folder...** twice, creating `dev`
   and `prod` inside it.
3. Select `main.tf`, `variables.tf`, and `outputs.tf` together: click the first,
   then `Ctrl+click` the other two.
4. **Drag them onto `environments/dev`.**
5. Drag `.terraform.lock.hcl` in as well. If you cannot see it, it is hidden
   behind the file filter: it is there, just below `outputs.tf`.

Now check the **Source Control** panel. The three files should appear as
**renames**, shown with an `R`, not as deletions plus additions. That is Git
following the move, so the file history follows too.

> Dragging in the Explorer is the same operation as `git mv`. VS Code tells Git
> about the rename, which is why the history survives.

State and the provider cache are not tracked by Git, so move them from a
terminal:

```powershell
move terraform.tfstate environments\dev\terraform.tfstate
Remove-Item -Recurse -Force .terraform
```

The command line equivalent of the drag-and-drop above:

```powershell
mkdir environments\dev
mkdir environments\prod

git mv main.tf environments\dev\main.tf
git mv variables.tf environments\dev\variables.tf
git mv outputs.tf environments\dev\outputs.tf
git mv .terraform.lock.hcl environments\dev\.terraform.lock.hcl
```

Now change into the dev directory. **Every Terraform command for the rest of the
week runs from an environment directory, never from the repository root.**

```powershell
cd environments\dev
```

## Part 3: Add the backend

Create `environments/dev/backend.tf`:

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-summit-tfstate"
    storage_account_name = "stsummittfstate<suffix>"
    container_name       = "tfstate"
    key                  = "orders-dev.terraform.tfstate"
  }
}
```

Replace `<suffix>`.

You can put the `backend` block inside the `terraform` block in `main.tf`
instead. A separate file is clearer, because the backend is the one thing that
differs between two otherwise identical environments, and reviewers should be
able to see it at a glance.

**The `key` is what separates the environments.** Same storage account, same
container, different blob. `orders-dev.terraform.tfstate` and
`orders-prod.terraform.tfstate` never touch each other.

> **Backend blocks cannot use variables.** Not `var.`, not `local.`, not
> interpolation. Terraform has to initialize the backend before it knows what
> any variable means. Every value in there is a literal. If you need it dynamic,
> the answer is `terraform init -backend-config=...`, which is how a pipeline
> supplies it.

## Part 4: Migrate

```powershell
terraform init
```

Terraform notices you have local state and a new backend, and asks:

```
Initializing the backend...
Do you want to copy existing state to the new backend?
  Pre-existing state was found while migrating the previous "local" backend
  to the newly configured "azurerm" backend. No existing state was found in
  the newly configured "azurerm" backend. Do you want to copy this state to
  the new "azurerm" backend? Enter "yes" to copy and "no" to start with an
  empty state.

  Enter a value:
```

Type `yes`.

> Read that prompt rather than reflexively agreeing. "No" means "start with an
> empty state," which in this situation would mean Terraform forgets your eleven
> resources. The distinction matters.

Now confirm nothing actually changed in Azure:

```powershell
terraform plan
```

**No changes.** You moved the bookkeeping, not the infrastructure. This is worth
sitting with: state is a record of what exists, entirely separate from the
things that exist.

### See it in Azure

```powershell
az storage blob list `
  --account-name stsummittfstate<suffix> `
  --container-name tfstate `
  --auth-mode login `
  -o table
```

There is your `orders-dev.terraform.tfstate` blob. Look at it in the portal too:
**Storage accounts** > your account > **Containers** > `tfstate`. Notice the
**Lease Status** column says *Unlocked*.

Your local `terraform.tfstate` is now a leftover. Terraform renamed it out of the
way:

```powershell
dir terraform.tfstate*
```

You will see `terraform.tfstate.backup` or similar. Leave it for now, it is a
safety copy. It is gitignored.

## Part 5: Watch the lock work

**Locking is why remote state is worth the trouble.** Two people applying the
same state at the same time can corrupt it. The azurerm backend prevents that
using a blob lease, and you do not configure anything to get it. (If you have
used the AWS S3 backend, this is the part where you would have had to create a
DynamoDB table.)

See it happen:

1. Open a **second** terminal in the same `environments/dev` directory. Set
   `ARM_SUBSCRIPTION_ID` and both `TF_VAR_` variables in it.
2. In the first terminal, start an apply and **do not answer the prompt**:

   ```powershell
   terraform apply
   ```

3. While it is sitting there, run this in the second terminal:

   ```powershell
   terraform plan
   ```

You get:

```
Error: Error acquiring the state lock

Error message: state blob is already locked
Lock Info:
  ID:        ...
  Operation: OperationTypeApply
  Who:       azureuser@vm-student01
  Created:   ...
```

Terraform tells you who holds the lock and what they are doing. Look at the
container in the portal while this is happening: **Lease Status** now says
*Leased*.

4. Go back to the first terminal and answer `no` to cancel the apply. The lock
   releases immediately.

> If a lock is ever left behind by a crashed run, `terraform force-unlock <ID>`
> clears it. Only do that when you are certain nothing is still running. Breaking
> a live lock is how state gets corrupted.

## Part 6: Scaffold production

Production does not exist yet. For now, give it a directory, a backend, and just
enough to prove the separation is real. You will fill it in later.

Create `environments/prod/backend.tf`:

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-summit-tfstate"
    storage_account_name = "stsummittfstate<suffix>"
    container_name       = "tfstate"
    key                  = "orders-prod.terraform.tfstate"
  }
}
```

Only the `key` differs from dev. Everything else is identical.

Create `environments/prod/main.tf`:

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

resource "azurerm_resource_group" "orders" {
  name     = "rg-summit-orders-prod"
  location = "eastus"

  tags = {
    environment = "prod"
    solution    = "orders"
    owner       = "ops-team"
    managed_by  = "terraform"
  }
}
```

Apply it:

```powershell
cd ..\prod
terraform init
terraform plan
terraform apply
```

One resource. Now look at your container again:

```powershell
az storage blob list `
  --account-name stsummittfstate<suffix> `
  --container-name tfstate `
  --auth-mode login `
  --query "[].name" -o tsv
```

```
orders-dev.terraform.tfstate
orders-prod.terraform.tfstate
```

**Two environments, two state files, one storage account.** This is the
structural point of the whole lab. If you ran `terraform destroy` in
`environments/dev` right now, it would destroy exactly the resources in the dev
state file and nothing else. Prod is not reachable from there. That is what
"blast radius" means in practice, and it is why the directories are separate
rather than being one configuration with an `environment` variable.

Go back to dev for the rest of the lab:

```powershell
cd ..\dev
```

## Part 7: Inspect state

You have used `state list` before. Now use it to answer a real question.

```powershell
terraform state list
```

Which resources are in this environment, and only this environment? Eleven. Run
the same command in `environments/prod` and you get one. State is scoped to the
directory.

Look at a single resource in detail:

```powershell
terraform state show azurerm_linux_virtual_machine.app
```

Scroll through it. Every attribute Azure reported back is recorded here,
including many you never wrote: `virtual_machine_id`, `private_ip_address`, the
computed OS disk name. This is how `plan` knows what "changed": it compares your
configuration against this record and against live Azure.

Now find the thing that should bother you:

```powershell
terraform state show azurerm_linux_virtual_machine.app | Select-String "admin_password"
```

There it is in plain text, in a file in Azure Storage. `sensitive = true` kept it
out of your terminal, not out of state. This is exactly why the state container
has public access disabled and why access to it should be restricted. Keeping the
secret out of state in the first place is the other half of the problem.

## Part 8: Rename a resource without destroying it

Say the team decides `azurerm_storage_container.data` is too vague a name and it
should be `orders_data`. In HCL that is a one-word edit. In Terraform's model it
is a different resource entirely, because the address changed.

Watch it happen. In `environments/dev/main.tf`, change:

```hcl
resource "azurerm_storage_container" "data" {
```

to:

```hcl
resource "azurerm_storage_container" "orders_data" {
```

Then:

```powershell
terraform plan
```

```
Plan: 1 to add, 0 to change, 1 to destroy.
```

Terraform wants to delete the container it knows as `.data` and build a new one
called `.orders_data`. Same container in Azure, same name, same everything. Only
the label in state is different, and Terraform has no way to know you meant it
as a rename.

On an empty container, who cares. On a database, a stateful disk, or a public IP
that DNS points at, this is an outage.

Fix it by telling state about the rename:

```powershell
terraform state mv azurerm_storage_container.data azurerm_storage_container.orders_data
```

```
Move "azurerm_storage_container.data" to "azurerm_storage_container.orders_data"
Successfully moved 1 object(s).
```

Then:

```powershell
terraform plan
```

**No changes.** Nothing was created, nothing was destroyed, and the container in
Azure never knew anything happened.

> **`state mv` has a catch, and it is a good one to notice now.** You just made
> a change to shared state from your laptop, by hand. It is not in the
> repository, it did not go through a pull request, and your teammate who pulls
> your rename will get the destroy-and-recreate plan you just avoided, because
> their state is the same state but they did not run the command... and in fact
> they will not, because state is shared. But in a pipeline, where nobody types
> commands, `state mv` is not available at all.
>
> There is a second way to record a rename: a `moved` block, which does the same
> job as a line of code that travels through the pull request and runs
> automatically. Use `moved` for renames you are committing. Keep `state mv` for
> interactive repair work.

## Part 9: `state rm`, carefully

`terraform state rm` tells Terraform to stop tracking a resource **without
deleting it in Azure**. It is the right tool when a resource should be managed
somewhere else, or by another team, or not at all any more.

It is also unforgiving, so check yourself first:

```powershell
terraform state rm -dry-run azurerm_storage_container.orders_data
```

```
Would remove azurerm_storage_container.orders_data
```

Nothing happened. `-dry-run` tells you exactly what the real command would take
out of state. Use it every time.

**Do not run it for real.** If you did, your container would still exist in
Azure but Terraform would no longer know about it, and the next `apply` would
try to create it and fail because the name is taken. Getting it back means
importing it.

| Command | Azure | State |
|---|---|---|
| `terraform destroy` | deleted | removed |
| `terraform state rm` | **untouched** | removed |
| `terraform import` | untouched | **added** |
| `terraform state mv` | untouched | re-labelled |

## Part 10: Commit

Format first, from a terminal:

```powershell
terraform -chdir=environments/dev fmt
terraform -chdir=environments/prod fmt
```

### Stage and commit

1. Open the **Source Control** panel (the branching icon in the activity bar).
2. Read the file list before you stage anything. You should see the renames into `environments/dev/`, the new `backend.tf` files,
   and the new prod files.
   There must be **no** `.tfstate` files and no `.terraform/` directory. If you
   see either, stop and tell the instructor.
3. Hover over **Changes** and click the **+** to stage everything.
4. In the message box, write:

   ```
   Move state to Azure Storage backend and split dev/prod environments
   ```

5. Click the **Commit** checkmark, then **Publish Branch**.

### Open the pull request and merge it

6. Click the **GitHub** icon in the activity bar, then **Create Pull Request**.
7. Confirm the base is **your own** repository's `main`.
8. Title it the same as your commit and click **Create**.
9. Open **Files Changed** and read your own diff.

VS Code opens two tabs. The file diff has no buttons; the tab named after the
pull request is the one with the merge button.

10. **Click the `#N` tab**, scroll to the bottom, and click **Merge Pull
    Request**, then confirm.
11. Click `Delete Branch...` next to *"Pull request successfully merged."* and
    choose both the local and remote branch.

> You cannot approve your own pull request. GitHub does not allow it, so the
> review box offers only **Comment**.

### Get back onto main

12. Click the branch name in the status bar, choose `main`, then click the sync
    icon.

The command line equivalent:

```powershell
git add -A
git commit -m "Move state to Azure Storage backend and split dev/prod environments"
git push -u origin feature/lab05-remote-state
# open and merge the pull request, then:
git switch main
git pull
```

## How to verify

- [ ] The `tfstate` container holds two blobs, one per environment
- [ ] `terraform plan` in `environments/dev` reports **No changes**
- [ ] `terraform plan` in `environments/prod` reports **No changes**
- [ ] `terraform state list` returns 11 resources in dev, 1 in prod
- [ ] A second terminal got a lock error while an apply was pending
- [ ] No state file is tracked by Git

## If you get stuck

| Error | What it means and what to do |
|---|---|
| `Failed to get existing workspaces: containers.Client#ListBlobs: ... AuthorizationPermissionMismatch` | Your `az login` identity cannot read the container. Confirm `az account show` points at the subscription you own the storage account in. |
| `Error: Backend configuration changed` | You edited `backend.tf` after initializing. Run `terraform init -reconfigure` (new empty state) or `terraform init -migrate-state` (carry the existing state over). Know which one you want. |
| `state blob is already locked` and nothing is running | A crashed run left the lease. Get the ID from the error and run `terraform force-unlock <ID>`. Be certain first. |
| `terraform init` asks to copy state and you have already migrated | You are in the wrong directory, or `.terraform` is stale. Check `pwd`, remove `.terraform`, and init again. |
| Plan in dev suddenly wants to create all 11 resources | Terraform is not seeing your state. Check the `key` in `backend.tf` matches the blob name, then `terraform init -reconfigure`. |
| `The specified container does not exist` | The bootstrap in Part 1 did not finish. Rerun the `az storage container create` command. |
| `StorageAccountAlreadyTaken` on bootstrap | Someone has your state account name. Pick a different suffix and use it consistently. |

## Cleanup

Nothing to destroy. Deallocate the VM at the end of the day if you are stopping
here:

```powershell
az vm deallocate --resource-group rg-summit-orders-dev --name vm-summit-orders-dev
```

**Never destroy `rg-summit-tfstate`.** Every remaining lab reads state from it.

## Congratulations!

Summit's Terraform state now lives somewhere durable, shared, versioned, and
locked, and the repository is shaped so `dev` and `prod` cannot damage each
other.

You also learned the three commands that repair state (`mv`, `rm`, and by
implication `import`), and, just as usefully, when not to reach for them.

The two directories are near-duplicates right now. That is the next thing to
fix.
