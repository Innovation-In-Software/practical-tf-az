# Lab 8: Secrets with Azure Key Vault

## Overview

Both of Summit's environments have the same defect. The VM admin password is an
input variable, which means it has to come from somewhere: an environment
variable you set by hand, your shell history, or eventually a `.tfvars` file that
gets committed by mistake.

In this lab you remove the variable entirely. Terraform reads the password from
Azure Key Vault at apply time, and nobody, including you, ever needs to know
what it is.

You will also do something uncomfortable on purpose: prove that Git remembers a
committed secret forever, and prove that `sensitive = true` does less than most
people assume.

## Objectives

By the end of this lab you can:

- Explain why deleting a committed secret does not remove it
- Read a secret from Azure Key Vault with a data source
- Replace an input variable with a value resolved at apply time
- Say precisely what `sensitive = true` protects and what it does not
- Explain how a pipeline gets access to the vault, and the ordering problem in
  granting it

## What you'll need

- Your repository with Lab 7 merged, both environments applied
- `az login` current, `ARM_SUBSCRIPTION_ID` set, your suffix


### Open a terminal at the repository root

Everything below runs from the top of your repository, not from inside
`environments`. If you switched branches from the command line just now, you are
already there. Otherwise, in the Explorer right-click the repository folder,
`az-tf-ops-<your-username>`, and choose **Open in Integrated Terminal**.

Check that the prompt ends in `az-tf-ops-<your-username>` before you run anything.
The seed script you run shortly is written as `.\scripts\...`, a path relative to
the repository root, so from any other folder PowerShell will not find it.

Windows blocks PowerShell script files by default. You should have lifted that in
the setup guide; if you have not, or if the script below fails with `running
scripts is disabled on this system`, run this once and try again:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
```


## Part 1: Prove that Git remembers

Three minutes, on a branch you throw away. Do it, because reading about it is
not the same.

This part is all command line on purpose. The point is what `git log` can still
see after you think you deleted something, and there is no button for that.

```powershell
git switch -c demo/leak
"db_password = SuperSecret123!" | Out-File -Encoding utf8 leak-demo.txt
git add leak-demo.txt
git commit -m "Add config"
```

Now notice your mistake and fix it, the way people actually do:

```powershell
Remove-Item leak-demo.txt
git add -A
git commit -m "Remove config, oops"
```

The file is gone. Your working directory is clean. Now look for the password:

```powershell
git log -p | Select-String "SuperSecret"
```

```
+db_password = SuperSecret123!
```

**It is still there, in full, in the history.** Anyone who clones the repository
gets it. If you had pushed, it is on GitHub, in every fork, and in the caches of
anything that scanned the repository. Deleting a file does not delete a commit.

Getting it out for real means rewriting history with `git filter-repo` or the
BFG, force-pushing, and telling everyone to re-clone. And even then, the correct
response is not "we cleaned the history," it is **"rotate the credential,
because you must assume it is compromised."**

Throw the branch away:

```powershell
git switch main
git branch -D demo/leak
```

Now check your real work:

```powershell
git log -p | Select-String "Summit-Lab-2026"
```

Nothing. You have been passing that password through `TF_VAR_` environment
variables since Lab 4 rather than putting it in a file, which is why your
history is clean. That was deliberate. This lab removes the last place it lives.


### Get the current version of the scripts

Your repository was created from a **template**, which takes a one-time copy. Fixes
made to the template afterwards do not reach you on their own, and `git pull` will
not find them either: your `origin` is your own repository, and a template leaves no
link back to the original.

So pull the current scripts in directly. From the repository root:

```powershell
git fetch https://github.com/Innovation-In-Software/az-tf-ops.git main
git checkout FETCH_HEAD -- scripts/
```

The first command downloads the template's history without adding a permanent
remote. The second takes only the `scripts/` folder out of it and writes it into
your working tree.

The scripts will show up as staged changes in Source Control. Commit them along
with your work for this lab, or run `git restore --staged scripts/` if you would
rather leave them unstaged. The files on disk are current either way. If nothing has
changed since you created your repository you will see no changes at all, which is
also a normal result.

> This overwrites everything under `scripts/`. That is what you want here, but if
> you have deliberately edited a script, copy your version somewhere else first.

### Start clean

Get onto `main`, pull, then branch. All of this is in VS Code.

1. Open your repository in VS Code: **File > Open Recent**, then
   `az-tf-ops-<your-username>`.
2. Click the branch name in the bottom left status bar and choose `main`.
3. Click the sync icon (the circular arrows) next to it to pull.
4. Click the branch name again, choose **Create new branch...**, and name it:

   ```
   feature/lab08-key-vault
   ```

5. Confirm the status bar now shows `feature/lab08-key-vault`.

The command line equivalent:

```powershell
cd C:\Users\Administrator\Downloads\terraform\labs\az-tf-ops-<your-username>
git switch main
git pull
git switch -c feature/lab08-key-vault
```


### Set your suffix

Every command below that names a storage account or a Key Vault reads your suffix
from `$env:SUFFIX`. Set it in this terminal, using your own four characters:

```powershell
$env:SUFFIX = "jr63"   # <-- CHANGE THIS to your own four characters
$env:SUFFIX
```

To set it permanently so no future lab asks again:

```powershell
[System.Environment]::SetEnvironmentVariable("SUFFIX", "jr63", "User")
```

## Part 2: Create the vaults

Run the seed script:

```powershell
.\scripts\seed-key-vault.ps1 -Suffix $env:SUFFIX
```

It creates a resource group `rg-summit-security` and two vaults,
`kv-summit-dev-<suffix>` and `kv-summit-prod-<suffix>`, each holding a randomly
generated secret called `vm-admin-password`.

It takes a couple of minutes, mostly waiting for role assignments to propagate.

### Why a script and not Terraform?

The same reason as the state backend in Lab 5. The vault holds the credential
Terraform needs in order to run. If Terraform created the vault, wrote the
secret, and then read the secret back in the same apply, the secret would have
to come from somewhere in the first place, and you are back where you started.

There is a second reason, and it is about ownership. At Summit the security team
owns vaults. The Orders team reads from them. Splitting that across a separate
resource group with separate RBAC is not bureaucracy; it means a mistake in the
Orders configuration cannot delete the credentials.

> **`rg-summit-security` is deliberately outside both environments.** A
> `terraform destroy` in `environments/dev` deletes the dev resource group and
> everything in it. If the vault lived there, it would go too.

### What the script created

```powershell
az keyvault list --resource-group rg-summit-security -o table
az keyvault secret list --vault-name "kv-summit-dev-$env:SUFFIX" -o table
```

Read the secret, just to confirm it exists:

```powershell
az keyvault secret show --vault-name "kv-summit-dev-$env:SUFFIX" --name vm-admin-password --query value -o tsv
```

That is the last time you need to look at it.

### Key Vault in one paragraph

A vault stores three kinds of thing: **secrets** (arbitrary strings, like
passwords and connection strings), **keys** (cryptographic keys you use without
extracting them), and **certificates**. You want secrets. Every access is
authenticated, authorized, logged, and versioned, and a deleted secret is
recoverable for a retention period rather than gone.

Access comes in two flavors, and the difference matters:

| Model | How it works | Use it when |
|---|---|---|
| **Azure RBAC** | Standard role assignments, like everything else in Azure. Roles such as *Key Vault Secrets User* (read) and *Key Vault Secrets Officer* (read and write) | New vaults. This is what Summit uses |
| **Access policies** | A per-vault list of principals and permitted operations, separate from Azure RBAC | Legacy vaults you inherit |

One thing catches everybody: **being Owner of the subscription does not let you
read a secret.** Owner is a control-plane role. It lets you delete the entire
vault but not look inside it. Reading secrets needs a data-plane role, which is
why the seed script granted you *Key Vault Secrets Officer* explicitly.

## Part 3: Read the secret with a data source

A **data source** reads something Terraform does not manage. You have used
resources, which create things. `data` blocks look things up.

Add to `environments/dev/main.tf`:

```hcl
# Look up the vault. Terraform does not manage it; the security team does.
data "azurerm_key_vault" "orders" {
  name                = var.key_vault_name
  resource_group_name = var.key_vault_resource_group_name
}

# Read the secret out of it, at plan and apply time, every run.
data "azurerm_key_vault_secret" "vm_admin_password" {
  name         = "vm-admin-password"
  key_vault_id = data.azurerm_key_vault.orders.id
}
```

The reference syntax has an extra word compared with resources:

| | Syntax |
|---|---|
| Resource | `azurerm_key_vault.orders.id` |
| Data source | `data.azurerm_key_vault.orders.id` |

Add the two variables to `environments/dev/variables.tf`:

```hcl
variable "key_vault_name" {
  description = "Name of the Key Vault holding this environment's secrets."
  type        = string
}

variable "key_vault_resource_group_name" {
  description = "Resource group containing the Key Vault. Owned by the security team."
  type        = string
  default     = "rg-summit-security"
}
```

And **delete** the `vm_admin_password` variable from `variables.tf` completely.
That is the point of the lab: not a better way to supply the variable, no
variable at all.

Add to `environments/dev/dev.tfvars`:

```hcl
key_vault_name                = "kv-summit-dev-<suffix>"
key_vault_resource_group_name = "rg-summit-security"
```

Type your four characters in place of `<suffix>`.

> A vault **name** in a committed file is fine. It is not a secret; it is an
> address. What matters is that reaching the contents requires an identity with
> a role assignment.

## Part 4: Point the VM at the secret

In `environments/dev/main.tf`, change the VM's password argument:

```hcl
resource "azurerm_linux_virtual_machine" "app" {
  ...
  admin_username                  = var.vm_admin_username
  admin_password                  = data.azurerm_key_vault_secret.vm_admin_password.value
  disable_password_authentication = false
  ...
}
```

One line. The password now travels from the vault, through Terraform's memory,
to the Azure API, and is never written down anywhere you control.

Stop exporting it:

```powershell
Remove-Item Env:\TF_VAR_vm_admin_password
```

Then:

```powershell
cd environments\dev
terraform plan -var-file dev.tfvars
```

### Expect a replacement, and understand why

```
  # azurerm_linux_virtual_machine.app must be replaced
-/+ resource "azurerm_linux_virtual_machine" "app" {
      ~ admin_password = (sensitive value) # forces replacement
    }

Plan: 1 to add, 0 to change, 1 to destroy.
```

The `-/+` and the words **forces replacement** are the ones to read.

The vault's password is not the one you set in Lab 4, so from Terraform's point
of view the admin password changed. Azure has no API to change the admin
password of an existing Linux VM through the VM resource, so the provider marks
`admin_password` as forcing replacement: the only way to honor the change is to
destroy the machine and build a new one.

This is a real and important behavior, not a lab artifact. **On a production
VM with anything on its disk, this plan is an outage.** The lesson is that
credential design is not something you retrofit cheaply, and the plan is what
tells you the cost before you pay it.

Our dev VM is empty and disposable, so take the replacement:

```powershell
terraform apply -var-file dev.tfvars
```

> **If you ever face this on a machine you cannot lose:** use
> `az vm user update` to change the password out of band, then add
> `lifecycle { ignore_changes = [admin_password] }` so Terraform stops trying to
> manage it. That is a compromise with a cost (Terraform no longer knows the
> real value), and it should be a deliberate, documented decision. On new
> builds, use SSH keys and avoid the problem.

Verify you can still get in:

```powershell
terraform output vm_ssh_command
$pw = az keyvault secret show --vault-name "kv-summit-dev-$env:SUFFIX" --name vm-admin-password --query value -o tsv
ssh azureuser@<the IP>
```

Paste `$pw` when prompted (`Write-Host $pw` if you need to see it).

## Part 5: What `sensitive` actually does

Add this to `environments/dev/outputs.tf`:

```hcl
output "vm_admin_password" {
  description = "Deliberately broken. Read the error, then fix it."
  value       = data.azurerm_key_vault_secret.vm_admin_password.value
}
```

```powershell
terraform plan -var-file dev.tfvars
```

```
Error: Output refers to sensitive values

  on outputs.tf line 30:
  30: output "vm_admin_password" {

To reduce the risk of accidentally exporting sensitive data that was intended
to be only internal, Terraform requires that any root module output containing
sensitive data be explicitly marked as sensitive.
```

Terraform tracked the sensitivity through the data source and refused to leak it
into output. Mark it:

```hcl
output "vm_admin_password" {
  description = "Admin password, redacted in output but present in state."
  value       = data.azurerm_key_vault_secret.vm_admin_password.value
  sensitive   = true
}
```

```powershell
terraform apply -var-file dev.tfvars
terraform output
```

```
vm_admin_password = <sensitive>
```

Redacted. Now defeat it in one command:

```powershell
terraform output -raw vm_admin_password
```

There it is, in plain text.

And find it in state:

```powershell
terraform state pull | Select-String "admin_password"
```

The password is in your state file, in Azure Storage, unencrypted at the
Terraform level.

| `sensitive = true` | |
|---|---|
| **Does** | Redact the value in `plan` and `apply` output |
| **Does** | Redact it in `terraform output` without `-raw` |
| **Does** | Propagate: anything derived from a sensitive value is also sensitive |
| **Does** | Keep secrets out of CI logs, which is where they most often leak |
| **Does not** | Encrypt anything |
| **Does not** | Keep the value out of the state file |
| **Does not** | Stop `terraform output -raw` or `terraform state pull` |

So the protection for the value in state is not `sensitive`. It is the state
backend: Azure Storage encrypts at rest, public access is off, and access needs
an Azure role. That is why Lab 5 spent time on those settings, and why the
answer to "who can read state" is a real access-control question in your
organization.

Now **delete that output**. It exists only for the demonstration. Real
configurations do not export credentials.

## Part 6: Do the same for production

Same three edits in `environments/prod`.

`environments/prod/main.tf`, add the data sources:

```hcl
data "azurerm_key_vault" "orders" {
  name                = var.key_vault_name
  resource_group_name = var.key_vault_resource_group_name
}

data "azurerm_key_vault_secret" "vm_admin_password" {
  name         = "vm-admin-password"
  key_vault_id = data.azurerm_key_vault.orders.id
}
```

and change the module input:

```hcl
module "app_vm" {
  source = "git::https://github.com/Innovation-In-Software/az-tf-ops-modules.git//linux-vm?ref=v1.1.0"
  ...
  admin_password = data.azurerm_key_vault_secret.vm_admin_password.value
  ...
}
```

`environments/prod/variables.tf`: add `key_vault_name` and
`key_vault_resource_group_name`, delete `vm_admin_password`.

`environments/prod/prod.tfvars`:

```hcl
key_vault_name                = "kv-summit-prod-<suffix>"
key_vault_resource_group_name = "rg-summit-security"
```

```powershell
cd ..\prod
terraform plan -var-file prod.tfvars
terraform apply -var-file prod.tfvars
```

Same VM replacement, same reason. Note the address in the plan is
`module.app_vm.azurerm_linux_virtual_machine.this`: the module passes the
sensitivity through, and the module's `admin_password` variable is declared
`sensitive = true` in `linux-vm/variables.tf`. Sensitivity is part of a module's
interface, and a module that fails to mark a credential sensitive is a module
worth opening an issue about.

## Part 7: How the pipeline will get in

Tomorrow, GitHub Actions runs `terraform apply` for you. It will hit
`data.azurerm_key_vault_secret` and need to read the vault. So:

1. The workflow authenticates to Azure as a **service principal (SP)**, an
   identity for software rather than a person.
2. That service principal needs **Key Vault Secrets User** on each vault.
3. Which means somebody has to grant it **before** the first pipeline run.

That ordering is the bootstrapping problem, and every team meets it. The vault
protects the credentials; the pipeline needs the credentials; something outside
the pipeline has to grant that access, by hand, once. That one manual step is the
root of trust for everything the pipeline does afterwards.

The credential you cannot avoid storing somewhere is the service principal's own
secret, which lives in GitHub Actions secrets. The modern answer to that is
**OIDC workload identity federation**: GitHub proves its identity to Entra ID
with a short-lived token and there is no stored secret at all. It is worth
looking into after the course. This course uses a service principal because that
is Summit's current standard.

## Part 8: Commit

Format first, from a terminal:

`-chdir` paths are relative to the folder you are standing in, and you have been
working inside `environments\dev`. Go back to the repository root first:

```powershell
cd C:\Users\Administrator\Downloads\terraform\labs\az-tf-ops-<your-username>
terraform -chdir=environments/dev fmt
terraform -chdir=environments/prod fmt
```

### Stage and commit

1. Open the **Source Control** panel. Read the file list before staging.
   Click each file to see its diff. You should see vault **names** and no vault
   contents. This is the lab where reading your own diff matters most.
   There must be **no** `.tfstate` files and no `.terraform/` directory.
2. Hover over **Changes** and click the **+** to stage everything.
3. In the message box, write:

   ```
   Read VM admin password from Key Vault instead of a variable
   ```

4. Click the **Commit** checkmark, then **Publish Branch**.

### Open the pull request and merge it

5. Click the **GitHub** icon in the activity bar, then **Create Pull Request**.
6. Confirm the base is **your own** repository's `main`.
7. Title it and describe it, then click **Create**.
8. Open **Files Changed** and read your own diff.
9. **Click the `#N` tab** (the file diff has no buttons), scroll to the bottom,
   click **Merge Pull Request**, and confirm.
10. Click `Delete Branch...` next to *"Pull request successfully merged."* and
    choose both the local and remote branch.
11. Click the branch name in the status bar, choose `main`, then click the sync
    icon to pull the merge down.

> You cannot approve your own pull request. GitHub does not allow it, so the
> review box offers only **Comment**.

The command line equivalent:

```powershell
git add -A
git commit -m "Read VM admin password from Key Vault instead of a variable"
git push -u origin feature/lab08-key-vault
# open and merge the pull request, then:
git switch main
git pull
```

## How to verify

- [ ] Neither environment declares a `vm_admin_password` variable
- [ ] `git log -p | Select-String "Summit-Lab-2026"` finds nothing
- [ ] `terraform plan` in both environments reports **No changes**
- [ ] Both VMs are reachable with the password from their vault
- [ ] `terraform state pull | Select-String admin_password` shows the value is
      still in state, and you can explain why that is acceptable

## If you get stuck

| Error | What it means and what to do |
|---|---|
| `does not have secrets get permission` | Your identity lacks the data-plane role. Rerun the seed script, or `az role assignment create --assignee <you> --role "Key Vault Secrets User" --scope <vault id>`. Being Owner is not enough. |
| `KeyVaultAlreadyExists` / `conflict` on create | A soft-deleted vault holds the name. `az keyvault purge --name "kv-summit-dev-$env:SUFFIX" --location eastus`, then rerun the script. |
| `Key Vault not found` from the data source | Check `key_vault_name` and `key_vault_resource_group_name` in your tfvars against `az keyvault list -o table`. |
| The role was granted but reads still fail | Propagation. Wait two minutes and try again. Role assignments are not instant. |
| Plan wants to replace the VM and you did not expect it | Expected in Part 4. The vault password differs from the old one, and `admin_password` forces replacement. |
| SSH rejects the password after the rebuild | You are using the old one. Fetch it from the vault with `az keyvault secret show`. |
| `Output refers to sensitive values` | Working as designed. Add `sensitive = true`, or do not output it. |

## Cleanup

Keep everything. Deallocate both VMs if you are done for the day:

```powershell
az vm deallocate -g rg-summit-orders-dev  -n vm-summit-orders-dev
az vm deallocate -g rg-summit-orders-prod -n vm-summit-orders-prod
```

**Do not delete `rg-summit-security`.** Every remaining lab reads from it.

## Congratulations!

That is Day 2. Summit's Orders platform now has shared, locked state, a
repository structured so environments cannot collide, configurations driven by
per-environment values, production built from reviewed shared modules, and
credentials that live in a vault rather than in anybody's shell.

You also know exactly what `sensitive = true` buys you, which is more than most
people who use it.

Day 3 is about the parts of the job nobody puts in the tutorial: the
infrastructure that already exists and was never in code, the pipeline that runs
this without you, and everything that goes wrong afterwards.
