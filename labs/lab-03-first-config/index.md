# Lab 3: Your First Terraform Configuration

## Overview

Time to write it yourself. In this lab you build the foundation of Summit's
Orders development environment: a resource group, a virtual network, and a
subnet inside that network. Three resources, wired together.

Then you run the whole lifecycle on them, the loop you will repeat for the rest
of your career with this tool:

```
write  ->  init  ->  validate  ->  plan  ->  apply
```

You will also look at the state file Terraform writes, which is how Terraform
knows which real resources belong to your configuration.

> **This lab creates real Azure resources in your subscription.** They are
> small and free or nearly free, and you will keep them: the next lab adds to this
> exact configuration.

## Objectives

By the end of this lab you can:

- Write a `terraform` block that pins the required version and provider
- Write `resource` blocks for an Azure resource group, virtual network, and subnet
- Make one resource reference another instead of repeating a value
- Run `init`, `fmt`, `validate`, `plan`, and `apply`, and explain what each does
- Read a plan and tell what Terraform intends to do before it does it
- Inspect state with `terraform state list` and `terraform state show`

## What you'll need

- Your own repository from Lab 2, at `C:\Users\Administrator\Downloads\terraform\labs\az-tf-ops-<your-username>`
- `ARM_SUBSCRIPTION_ID` set in your terminal (see the [setup guide](../setup/index.md))
- Your 4-character student suffix

Confirm you are ready:

```powershell
terraform version
az account show --query name -o tsv
$env:ARM_SUBSCRIPTION_ID
```

All three should print something sensible. If `$env:ARM_SUBSCRIPTION_ID` prints
nothing, set it before going further.

## Part 1: Branch first

Old habits: open the editor and start typing. New habit: branch first.

1. Open `C:\Users\Administrator\Downloads\terraform\labs\az-tf-ops-<your-username>` in VS Code.
2. Click the branch name in the status bar, choose **Create new branch...**,
   and name it `feature/lab03-network-foundation`.

```powershell
git switch -c feature/lab03-network-foundation
```

## Part 2: The terraform block

At the root of your repository, create a file named `main.tf`.

Start with the block that configures Terraform itself. This is not infrastructure;
it is the contract for which versions are allowed to run this configuration.

```hcl
terraform {
  # import blocks, moved blocks, and config generation all need a recent CLI.
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

Three things worth understanding before you move on.

**`required_version = ">= 1.9"`** means Terraform refuses to run this
configuration on anything older. Without it, a teammate on an older CLI gets a
syntax error on `import` blocks and no explanation of why.

**`source = "hashicorp/azurerm"`** is the provider: the plugin that knows how to
talk to the Azure Resource Manager API. Terraform itself knows nothing about
Azure. Every resource type you write comes from a provider.

**`version = "~> 4.0"`** pins to the version 4 line. It allows `4.81`, `4.90`,
and so on, but never `5.0`. Providers make breaking changes in major versions,
and an unpinned provider means your configuration can change behavior overnight
without anyone editing it. Version 4 of `azurerm` in particular requires an
explicit subscription id, which is why you set `ARM_SUBSCRIPTION_ID`.

**`features {}`** is required by the `azurerm` provider even when empty. It is
where you would opt into behaviors like "purge Key Vaults on destroy." Leave it
empty.

## Part 3: The resource group

Add this below the provider block:

```hcl
resource "azurerm_resource_group" "orders" {
  name     = "rg-summit-orders-dev"
  location = "eastus"

  tags = {
    environment = "dev"
    solution    = "orders"
    owner       = "ops-team"
    managed_by  = "terraform"
  }
}
```

Read the first line carefully, because every resource block in Terraform has the
same shape:

```
resource "azurerm_resource_group" "orders" {
   ^          ^                      ^
   |          |                      |
   |          |                      the LOCAL name you chose. Only Terraform
   |          |                      uses it. It is how other blocks refer to
   |          |                      this one.
   |          the RESOURCE TYPE, defined by the provider. The azurerm_ prefix
   |          tells you which provider owns it.
   the block type: this is a thing Terraform manages
```

The address of this resource, the thing you will see in plans and in state, is
`azurerm_resource_group.orders`: type plus local name.

> The `managed_by = "terraform"` tag is not decoration. When someone finds a
> resource group in the portal six months from now, that tag tells them not to
> edit it by hand.

## Part 4: The virtual network and subnet

A **virtual network (VNet)** is your private address space in Azure. A
**subnet** is a slice of it that resources actually attach to.

Add both:

```hcl
resource "azurerm_virtual_network" "orders" {
  name                = "vnet-summit-orders-dev"
  resource_group_name = azurerm_resource_group.orders.name
  location            = azurerm_resource_group.orders.location
  address_space       = ["10.10.0.0/16"]

  tags = azurerm_resource_group.orders.tags
}

resource "azurerm_subnet" "app" {
  name                 = "snet-app"
  resource_group_name  = azurerm_resource_group.orders.name
  virtual_network_name = azurerm_virtual_network.orders.name
  address_prefixes     = ["10.10.1.0/24"]
}
```

Here is the idea this lab is really about.

Look at `resource_group_name = azurerm_resource_group.orders.name`. You did not
type `"rg-summit-orders-dev"` a second time. You **referenced** the resource
group's `name` attribute. Two things follow from that:

1. **One source of truth.** Change the resource group name in one place and
   everything that references it follows.
2. **Terraform now knows the order.** Nobody told it "create the resource group
   first." It worked that out from the reference. That implied ordering, across
   every resource in your configuration, is called the dependency graph.

Notice the subnet has no `tags` argument and no `location`. Subnets in Azure do
not support either: they inherit the network's region and cannot be tagged. This
is normal. Every resource type has its own set of arguments, and the way to find
them is the provider documentation, which is one keystroke away in a moment.

### Try the extension

Put your cursor inside the `azurerm_subnet` block, on a blank line, and press
`Ctrl+Space`. The HashiCorp Terraform extension lists every valid argument.
Hover over `address_prefixes` and it shows the documentation inline. Use this
constantly. Nobody memorizes provider schemas.

## Part 5: Initialize

Open a terminal in the repository folder (right-click the folder in the Explorer,
**Open in Integrated Terminal**) and run:

```powershell
terraform init
```

You should see Terraform find the `azurerm` provider, download it, and finish
with **"Terraform has been successfully initialized!"**.

Two new things appeared in your folder:

| Item | What it is |
|---|---|
| `.terraform/` | The downloaded provider binary. Large, machine-specific, **never committed**. |
| `.terraform.lock.hcl` | The exact provider version and checksums that got resolved. Small, **always committed**, so your teammate and the pipeline get the identical provider. |

Both are already handled by the `.gitignore` in your repository. Take a look at
it if you want to confirm.

> `terraform init` is safe to run any time and you will run it often: after
> adding a provider, after adding a module, after changing the backend.

## Part 6: Format and validate

Two fast checks before you ask Azure anything.

```powershell
terraform fmt
```

This rewrites your files in the canonical style: consistent indentation, aligned
`=` signs. It prints the name of any file it changed. Run it before every commit
and code review stops being about whitespace.

```powershell
terraform validate
```

This checks the configuration is internally consistent: valid syntax, arguments
that actually exist, references that point at something real. It does **not**
talk to Azure, so it is instant. You should see **"Success! The configuration is
valid."**

### Break it on purpose

You will see plenty of errors this week. Reading them accurately is a skill, so
practice on one you caused deliberately.

1. In `main.tf`, change `address_prefixes` to `address_prefix` (drop the `es`).
2. Run `terraform validate`.

You get something like:

```
Error: Unsupported argument

  on main.tf line 30, in resource "azurerm_subnet" "app":
  30:   address_prefix = ["10.10.1.0/24"]

An argument named "address_prefix" is not expected here. Did you mean
"address_prefixes"?
```

Your line number will differ from the one above. That is fine: it points at
wherever the argument landed in *your* file.

Notice the shape of it: the error type, the exact file and line, the offending
text, a plain explanation, and in this case the fix itself. Terraform errors are
usually this good. Read them top to bottom rather than skimming for red.

> `address_prefix` is not a typo somebody invented. It was the correct argument
> in version 2 of the `azurerm` provider and was removed in version 4. Not every
> error is this helpful: sometimes an argument is simply gone and the message
> does not tell you what replaced it.

3. Put the `es` back and run `terraform validate` again.

## Part 7: Plan

```powershell
terraform plan
```

Now Terraform does talk to Azure. It reads your configuration, checks state (you
have none yet), asks Azure what exists, and reports what it would do to make
reality match your file.

Read the output rather than scrolling past it:

```
Terraform will perform the following actions:

  # azurerm_resource_group.orders will be created
  + resource "azurerm_resource_group" "orders" {
      + id       = (known after apply)
      + location = "eastus"
      + name     = "rg-summit-orders-dev"
      + tags     = {
          + "environment" = "dev"
          ...
        }
    }
  ...

Plan: 3 to add, 0 to change, 0 to destroy.
```

The symbols are the whole language of a plan:

| Symbol | Meaning |
|---|---|
| `+` | create |
| `-` | destroy |
| `~` | change in place |
| `-/+` | destroy **and then** recreate (downtime, pay attention) |

`(known after apply)` means Azure assigns that value, so Terraform cannot know
it yet. Resource ids and IP addresses are the usual ones.

**"Plan: 3 to add, 0 to change, 0 to destroy"** is the line to read first, every
single time.

> Get in the habit now: never type `terraform apply` without reading the plan
> that preceded it. This is the single practice that separates people who trust
> Terraform from people who are afraid of it.

## Part 8: Apply

```powershell
terraform apply
```

Terraform shows the plan again and asks for confirmation. Type `yes` and press
Enter. Anything other than exactly `yes` cancels.

It takes under a minute. You should end with:

```
Apply complete! Resources: 3 added, 0 changed, 0 destroyed.
```

### Verify in the portal

1. Go to [portal.azure.com](https://portal.azure.com) and search for **Resource
   groups**.
2. Open `rg-summit-orders-dev`. Your virtual network is inside it.
3. Open the virtual network, then **Subnets** on the left. `snet-app` is there
   with `10.10.1.0/24`.
4. Back on the resource group, look at **Tags**. All four are there, spelled
   identically, because they came from one place.

## Part 9: Look at state

Terraform wrote a file called `terraform.tfstate` in your folder. It is the map
between the names in your configuration and the real resources in Azure.

List everything Terraform is tracking:

```powershell
terraform state list
```

```
azurerm_resource_group.orders
azurerm_subnet.app
azurerm_virtual_network.orders
```

Those are addresses, not Azure names. Now look at one in detail:

```powershell
terraform state show azurerm_virtual_network.orders
```

You get every attribute Terraform recorded, including the Azure resource id:

```
id = "/subscriptions/<sub>/resourceGroups/rg-summit-orders-dev/providers/Microsoft.Network/virtualNetworks/vnet-summit-orders-dev"
```

That id is how Terraform addresses the resource in Azure.

Open `terraform.tfstate` in VS Code and read it once, so you know what is in it.
Then note two rules:

- **Never edit it by hand.** Use `terraform state` commands.
- **Never commit it.** It sits on your laptop right now, and it can contain
  secrets in plain text.

### Prove that plan is idempotent

Run the plan again without changing anything:

```powershell
terraform plan
```

```
No changes. Your infrastructure matches the configuration.
```

That sentence is the goal state of every Terraform repository. Reality matches
the code.

## Part 10: Commit your work

Your configuration currently exists only on your branch. The next lab starts from
`main`. If you stop after pushing, the next lab will not work, so complete every
step below.

### Stage and commit

1. Open the **Source Control** panel (the branching icon in the activity bar).
2. You should see `main.tf` and `.terraform.lock.hcl` under **Changes**, and
   **nothing else**. In particular there must be no `terraform.tfstate` and no
   `.terraform/`. If either appears, your `.gitignore` is not doing its job:
   tell the instructor before you push.
3. Hover over **Changes** and click the **+** to stage both files.
4. In the message box, write:

   ```
   Add resource group, virtual network, and subnet for orders dev
   ```

5. Click the **Commit** checkmark.
6. Click **Publish Branch**.

### Open the pull request and merge it

7. Click the **GitHub** icon in the activity bar, then **Create Pull Request**.
8. Confirm the base is **your own** repository's `main`.
9. Title it the same as your commit and click **Create**.

VS Code now opens **two** editor tabs, and only one of them can merge:

| Tab | What it is |
|---|---|
| `#N Add resource group, virtual network...` | The pull request: description, commits, and the merge button |
| `Changes in Commit ...` or a file diff | Just the code. No buttons |

10. **Click the `#N` tab**, the one named after your pull request. Scroll to the
    bottom and click **Merge Pull Request**, then confirm.

If you closed that tab, click the pull request again under **Pull Requests** in
the **GitHub Pull Request** panel on the left. The GitHub web page has the same
button if you prefer the browser.

### Get back onto main

11. Click the branch name in the bottom left status bar and choose `main`.
12. Click the sync icon next to it to pull the merge down.

**Now confirm it worked.** With `main` checked out, `main.tf` must still be
visible in the Explorer. If it disappeared when you switched branches, the merge
did not happen and your work is still only on the feature branch. Go back to
step 7.

The command line equivalent for all of Part 10:

```powershell
git add main.tf .terraform.lock.hcl
git commit -m "Add resource group, virtual network, and subnet for orders dev"
git push -u origin feature/lab03-network-foundation
# open and merge the pull request, then:
git switch main
git pull
```

> **You cannot approve your own pull request.** GitHub rejects it: *"Can not
> approve your own pull request."* You are merging it unreviewed, which is not
> how it works on a real team, and it is only acceptable here because this
> repository is yours alone. Later you will make even this impossible.

## How to verify

- [ ] `terraform plan` reports **No changes**
- [ ] `terraform state list` shows exactly three resources
- [ ] The portal shows `rg-summit-orders-dev` with the VNet and subnet inside
- [ ] Your pull request is **merged**, and the status bar shows `main`
- [ ] **With `main` checked out, `main.tf` is still there.** This is the one the
      next lab depends on. If `main.tf` vanishes when you switch to `main`, your
      work never reached it

## If you get stuck

| Error | What it means and what to do |
|---|---|
| `subscription_id is a required provider property` | `ARM_SUBSCRIPTION_ID` is not set in this terminal. Set it and rerun. |
| `Error: building account: ... token` | Your `az login` expired. Run `az login` again. |
| `A resource with the ID ... already exists` | That resource already exists in Azure but not in your state, usually from a previous attempt. Delete it in the portal and apply again. |
| `InvalidCidrNotation` or an address overlap | Check `address_space` is `["10.10.0.0/16"]` and the subnet is inside it. |
| `Reference to undeclared resource` | A typo in a reference. The local name on the left of the dot must match a `resource` block exactly. |
| `terraform apply` hangs at "Still creating..." | Normal. Networking resources take up to a minute. Give it two before worrying. |

## Cleanup

**Do not destroy anything.** The next lab builds directly on top of what you just
created.

If you want to see how `destroy` works, run `terraform plan -destroy` to preview
it, and then do not run the real thing:

```powershell
terraform plan -destroy
```

It should report `Plan: 0 to add, 0 to change, 3 to destroy.` That is the
preview. Close the terminal and leave the resources alone.

## Congratulations!

You wrote a Terraform configuration from scratch, ran the full lifecycle against
a real Azure subscription, and got the sentence that means everything is in
order: **No changes. Your infrastructure matches the configuration.**

You also saw resources reference each other rather than repeat values, which is
what makes a configuration maintainable instead of a pile of literals.
