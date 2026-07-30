# Lab 6: Variables, Locals, Outputs, and Expressions

## Overview

Open `environments/dev/main.tf` and look at what is hardcoded.

Some of it you already handled in Lab 3. `"eastus"` is written once, on the
resource group, and six other resources reference
`azurerm_resource_group.orders.location` rather than repeating it. Same with the
tags. That is referencing working exactly as intended.

The problem is what referencing cannot fix. **`summit-orders-dev` is typed into
seven resource names**, once each:

```
rg-summit-orders-dev        pip-summit-orders-dev
vnet-summit-orders-dev      nic-summit-orders-dev
nsg-summit-orders-dev       vm-summit-orders-dev
                            stsummitordersdev<suffix>
```

There is nothing to reference. Each name is its own literal. `"eastus"`,
`"Standard_F1als_v7"`, `"LRS"`, and `"10.10.0.0/16"` have the same shape: written
once, but written as a decision rather than as an input, so nothing can vary them.

Now imagine building `prod` by copying that file and editing every one of those.
That is how two environments quietly drift apart: someone fixes a typo in dev
and nobody remembers to fix it in prod.

This lab makes the dev configuration describe **a Summit environment** rather
than **the dev environment**, using:

- **input variables** for the things that differ between environments
- **validation** so a bad value fails in half a second instead of halfway
  through an apply
- **locals** for values you compute once from those variables
- **`.tfvars` files** so `dev` and `prod` are the same configuration with
  different numbers
- **`for_each`** so a list of similar things is one resource block, not five

The measure of success is unusual and worth stating up front: when you are done
refactoring, **`terraform plan` should say almost nothing changed**. You are
rewriting how the configuration is expressed, not what it builds.

## Objectives

By the end of this lab you can:

- Declare typed input variables with descriptions, defaults, and validation
- Supply values from a `.tfvars` file and explain variable precedence
- Compute derived names and tags in a `locals` block
- Use `merge`, `replace`, `format`, `coalesce`, and `cidrsubnet`
- Write a conditional expression
- Choose `for_each` over `count`, and explain the failure mode `count` has
- Read the plan that a resource address change produces

## What you'll need

- Your repository with Lab 5 merged, state in Azure Storage
- The usual environment variables set:

### Start clean

Get onto `main`, pull, then branch. All of this is in VS Code.

1. Open your repository in VS Code: **File > Open Recent**, then
   `az-tf-ops-<your-username>`.
2. Click the branch name in the bottom left status bar and choose `main`.
3. Click the sync icon (the circular arrows) next to it to pull.
4. Click the branch name again, choose **Create new branch...**, and name it:

   ```
   feature/lab06-variables
   ```

5. Confirm the status bar now shows `feature/lab06-variables`.

The command line equivalent:

```powershell
cd C:\Users\Administrator\Downloads\terraform\labs\az-tf-ops-<your-username>
git switch main
git pull
git switch -c feature/lab06-variables
```

### Set your variables and check the plan

Open a terminal with ``Ctrl+` `` for these:

```powershell
$env:SUFFIX = "jr63"   # <-- CHANGE THIS to your own four characters
$env:TF_VAR_allowed_ssh_source = "$(Invoke-RestMethod https://api.ipify.org)/32"
$env:TF_VAR_vm_admin_password = "Summit-Lab-2026!"

cd environments\dev
terraform plan
```

Clean plan before you start.

## Part 1: Declare the variables

Replace the whole contents of `environments/dev/variables.tf` with this. Read the
comments; they are the lesson.

```hcl
# ---------------------------------------------------------------------------
# Identity of this environment. These three drive every name and tag.
# ---------------------------------------------------------------------------

variable "org" {
  description = "Short organization prefix used in resource names."
  type        = string
  default     = "summit"
}

variable "solution" {
  description = "The solution this environment belongs to."
  type        = string
  default     = "orders"
}

variable "environment" {
  description = "Environment name. Drives naming, tagging, and sizing decisions."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "location" {
  description = "Azure region for every resource in this environment."
  type        = string
  default     = "eastus"

  validation {
    condition     = contains(["eastus", "eastus2", "centralus"], var.location)
    error_message = "Summit only deploys to eastus, eastus2, or centralus."
  }
}

variable "owner" {
  description = "Team responsible for this environment. Goes on every tag."
  type        = string
  default     = "ops-team"
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------

variable "vnet_address_space" {
  description = "Address space for the virtual network."
  type        = list(string)
}

# ---------------------------------------------------------------------------
# Compute
# ---------------------------------------------------------------------------

variable "vm_size" {
  description = "Azure VM size for the application server."
  type        = string
  default     = "Standard_F1als_v7"
}

variable "vm_admin_username" {
  description = "Admin user created on the VM."
  type        = string
  default     = "azureuser"
}

variable "vm_admin_password" {
  description = "Admin password for the VM. Supplied at run time, never committed."
  type        = string
  sensitive   = true
}

variable "allowed_ssh_source" {
  description = "The one public IP allowed to reach the VM on port 22, in CIDR form."
  type        = string

  validation {
    condition     = can(cidrhost(var.allowed_ssh_source, 0))
    error_message = "allowed_ssh_source must be valid CIDR notation, for example 203.0.113.7/32."
  }
}

# ---------------------------------------------------------------------------
# Storage
# ---------------------------------------------------------------------------

variable "storage_name_suffix" {
  description = "Your 4-character student suffix. Storage account names are globally unique."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{2,6}$", var.storage_name_suffix))
    error_message = "storage_name_suffix must be 2 to 6 lowercase letters or digits."
  }
}

variable "storage_containers" {
  description = "Blob containers to create in the environment storage account, keyed by name."
  type = map(object({
    access_type = string
  }))

  default = {
    "orders-data" = { access_type = "private" }
    "orders-logs" = { access_type = "private" }
  }
}
```

### What to notice

**`description` on every variable.** These are not decoration. Terraform prints
the description when a
value is missing, and tools like `terraform-docs` build the module documentation
from it. When you read a module somebody else wrote, these descriptions are what
you read first.

**Types are declared.** `list(string)`, `map(object({...}))`. Terraform will
reject a value of the wrong shape before it makes a single API call.

**Some variables have no default.** `environment`, `vnet_address_space`,
`vm_admin_password`, `allowed_ssh_source`, `storage_name_suffix`. A missing
default means "this is required, and there is no sensible guess." Compare that
with `location`, which defaults to `eastus` because that is Summit's home region
and overriding it is the exception.

**`validation` blocks fail fast.** `contains(...)` restricts to a list.
`can(cidrhost(...))` is the standard trick for "is this parseable as CIDR": `can`
runs an expression and returns `true` or `false` instead of erroring. `regex`
enforces a name pattern.

Try one:

```powershell
terraform plan -var="environment=production" -var="vnet_address_space=[]" -var="storage_name_suffix=x"
```

```
Error: Invalid value for variable
  environment must be one of: dev, staging, prod.

Error: Invalid value for variable
  storage_name_suffix must be 2 to 6 lowercase letters or digits.
```

Two errors, instantly, before Azure was contacted. Without validation you would
have found out when a resource name was rejected four minutes into an apply.

## Part 2: Compute names and tags once, in locals

A variable is an input. A **local** is a value you work out from inputs, named
so you only write the logic once.

Add this to the top of `environments/dev/main.tf`, just below the `provider`
block:

```hcl
locals {
  # summit-orders-dev
  name_prefix = "${var.org}-${var.solution}-${var.environment}"

  # stsummitordersdev + your suffix. Storage account names allow no hyphens,
  # so strip them out rather than maintaining a second naming variable.
  storage_account_name = "st${replace(local.name_prefix, "-", "")}${var.storage_name_suffix}"

  # Applied to everything. One definition means one spelling.
  tags = {
    environment = var.environment
    solution    = var.solution
    owner       = var.owner
    managed_by  = "terraform"
  }

  # Dev gets the cheapest redundancy; anything else gets zone redundancy.
  storage_replication_type = var.environment == "prod" ? "GRS" : "LRS"
}
```

Three techniques in eleven lines.

**String interpolation.** `"${var.org}-${var.solution}-${var.environment}"`
substitutes each expression into the string.

**A function.** `replace(local.name_prefix, "-", "")` turns
`summit-orders-dev` into `summitordersdev`. Note that a local can reference
another local.

**A conditional expression.** `condition ? value_if_true : value_if_false`. Read
it as "if the environment is prod, GRS, otherwise LRS."

### Play with expressions before you commit them

`terraform console` gives you an interactive evaluator. It is the fastest way to
answer "what does this function actually return?"

```powershell
terraform console
```

Everything below is a plain function call on literal values, so no variables are
needed. Terraform only asks for a variable's value when you reference it, and
`local.name_prefix` is the only thing here that would.

> If you do want to evaluate `local.*` or `var.*`, the console needs values, and
> those live in the `.tfvars` file you write in Part 4. Come back after that and
> run `terraform console -var-file dev.tfvars` to inspect your own locals. Doing
> it now fails with `Given variables file dev.tfvars does not exist`, because you
> have not written it yet.

Try these one at a time. Type the expression, press Enter, and the console prints
the result straight back.

**Strip the hyphens out of a name.**

```
replace("summit-orders-dev", "-", "")
```

```
"summitordersdev"
```

This is exactly how `local.storage_account_name` gets built. Storage account
names allow no hyphens, so the name prefix is reused with them removed rather
than keeping a second variable that could disagree with the first.

**Carve a subnet out of a larger range.**

```
cidrsubnet("10.10.0.0/16", 8, 1)
```

```
"10.10.1.0/24"
```

Three arguments: the range to cut up, how many bits to add to the prefix, and
which of the resulting blocks you want. Adding 8 bits to a `/16` gives `/24`
subnets, and index `1` is the second one, `10.10.1.0/24`. That is where
`snet-app` comes from, so changing `vnet_address_space` moves the subnet with it
instead of leaving a hardcoded range behind.

**Combine two maps.**

```
merge({ a = 1, b = 2 }, { b = 99, c = 3 })
```

```
{
  "a" = 1
  "b" = 99
  "c" = 3
}
```

Note `b`: the right-hand map wins. That is what lets a single resource add or
override one tag without redefining the whole standard set, as in
`merge(local.tags, { role = "app-server" })`.

**Build a string with placeholders.**

```
format("vm-%s-%02d", "app", 3)
```

```
"vm-app-03"
```

`%s` takes a string, `%02d` takes a number and pads it to two digits with a
leading zero. Useful for numbered resources, where `vm-app-03` sorts correctly
next to `vm-app-12` and `vm-app-3` does not.

**Pick the first value that is actually set.**

```
coalesce(null, "", "fallback")
```

```
"fallback"
```

It skips `null` **and** the empty string, which is the behaviour you want for
"use the override if someone supplied one, otherwise the default". A plain `!=
null` check would have accepted the empty string.

**Compare two values.**

```
upper("dev") == "DEV"
```

```
true
```

The result is a boolean, and that is the point: a variable `validation` block
needs an expression that evaluates to `true` or `false`. You can test a condition
here before committing it, rather than finding out during a plan.

Type `exit` to leave the console.

> Two more functions appear in the validation blocks you wrote in Part 1, and you
> can try them here the same way: `contains(["dev", "prod"], "dev")` asks whether
> a value is in a list, and `can(regex("^[a-z]+$", "abc"))` returns whether an
> expression succeeded rather than its value.

## Part 3: Rewrite the resources

Open `environments/dev/main.tf` and replace the literals in the resource blocks,
leaving the `terraform`, `provider`, and `locals` blocks you just wrote alone.

Every change is listed below, `-` for the line you remove and `+` for the line
that replaces it. Work down the file resource by resource.

**The resource group.** The tag map moves into `local.tags`, so four lines
collapse into one:

```diff
 resource "azurerm_resource_group" "orders" {
-  name     = "rg-summit-orders-dev"
-  location = "eastus"
-
-  tags = {
-    environment = "dev"
-    solution    = "orders"
-    owner       = "ops-team"
-    managed_by  = "terraform"
-  }
+  name     = "rg-${local.name_prefix}"
+  location = var.location
+  tags     = local.tags
 }
```

**The virtual network.** Note the tags line: every other resource referenced
`azurerm_resource_group.orders.tags`, and they all now point at `local.tags`
instead. That is the same value, sourced from the definition rather than from
another resource.

```diff
 resource "azurerm_virtual_network" "orders" {
-  name                = "vnet-summit-orders-dev"
+  name                = "vnet-${local.name_prefix}"
   resource_group_name = azurerm_resource_group.orders.name
   location            = azurerm_resource_group.orders.location
-  address_space       = ["10.10.0.0/16"]
-
-  tags = azurerm_resource_group.orders.tags
+  address_space       = var.vnet_address_space
+  tags                = local.tags
 }
```

**The subnet.** The hardcoded `/24` is derived from the VNet range, so the two
can never disagree:

```diff
-  address_prefixes     = ["10.10.1.0/24"]
+  address_prefixes     = [cidrsubnet(var.vnet_address_space[0], 8, 1)]
```

**The NSG, public IP, and NIC.** All three take the same two changes, the name
and the tags:

```diff
-  name                = "nsg-summit-orders-dev"
+  name                = "nsg-${local.name_prefix}"
-  tags = azurerm_resource_group.orders.tags
+  tags                = local.tags

-  name                = "pip-summit-orders-dev"
+  name                = "pip-${local.name_prefix}"
-  tags = azurerm_resource_group.orders.tags
+  tags                = local.tags

-  name                = "nic-summit-orders-dev"
+  name                = "nic-${local.name_prefix}"
-  tags = azurerm_resource_group.orders.tags
+  tags                = local.tags
```

The NSG rule and the subnet association need no changes: they only reference
other resources and hold no literals of their own.

**The virtual machine.** The size and username become inputs, and the tags gain
one extra key with `merge`:

```diff
-  name                = "vm-summit-orders-dev"
+  name                = "vm-${local.name_prefix}"
-  size                = "Standard_F1als_v7"
+  size                = var.vm_size
-  admin_username                  = "azureuser"
+  admin_username                  = var.vm_admin_username
-  tags = azurerm_resource_group.orders.tags
+  tags = merge(local.tags, { role = "app-server" })
```

**The storage account.** The name and redundancy both come from `locals`, which
is where the `prod ? GRS : LRS` decision lives:

```diff
-  name                     = "stsummitordersdev<suffix>"
+  name                     = local.storage_account_name
-  account_replication_type = "LRS"
+  account_replication_type = local.storage_replication_type
-
-  tags = azurerm_resource_group.orders.tags
+  tags                     = local.tags
```

**The storage container.** This one changes shape rather than just values. One
block with a hardcoded name becomes one block driven by a map, which is what
lets you add a second container by editing a list:

```diff
-resource "azurerm_storage_container" "orders_data" {
-  name                  = "orders-data"
+resource "azurerm_storage_container" "this" {
+  for_each = var.storage_containers
+
+  name                  = each.key
   storage_account_id    = azurerm_storage_account.orders.id
-  container_access_type = "private"
+  container_access_type = each.value.access_type
 }
```

> The container's **address** changes here, from
> `azurerm_storage_container.orders_data` to
> `azurerm_storage_container.this["orders-data"]`. That matters, and Part 6 deals
> with it before you apply anything.

### The finished file

For reference, here is the whole of `environments/dev/main.tf` after the
`terraform`, `provider`, and `locals` blocks:

```hcl
resource "azurerm_resource_group" "orders" {
  name     = "rg-${local.name_prefix}"
  location = var.location
  tags     = local.tags
}

resource "azurerm_virtual_network" "orders" {
  name                = "vnet-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.orders.name
  location            = azurerm_resource_group.orders.location
  address_space       = var.vnet_address_space
  tags                = local.tags
}

resource "azurerm_subnet" "app" {
  name                 = "snet-app"
  resource_group_name  = azurerm_resource_group.orders.name
  virtual_network_name = azurerm_virtual_network.orders.name

  # Carve the first /24 out of whatever address space this environment uses,
  # instead of hardcoding it in two places that can disagree.
  address_prefixes = [cidrsubnet(var.vnet_address_space[0], 8, 1)]
}

resource "azurerm_network_security_group" "orders" {
  name                = "nsg-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.orders.name
  location            = azurerm_resource_group.orders.location
  tags                = local.tags
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

resource "azurerm_public_ip" "app" {
  name                = "pip-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.orders.name
  location            = azurerm_resource_group.orders.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_network_interface" "app" {
  name                = "nic-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.orders.name
  location            = azurerm_resource_group.orders.location

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.app.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.app.id
  }

  tags = local.tags
}

resource "azurerm_linux_virtual_machine" "app" {
  name                = "vm-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.orders.name
  location            = azurerm_resource_group.orders.location
  size                = var.vm_size

  admin_username                  = var.vm_admin_username
  admin_password                  = var.vm_admin_password
  disable_password_authentication = false

  network_interface_ids = [azurerm_network_interface.app.id]

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

  # merge() adds a role tag on top of the standard set, without redefining it.
  tags = merge(local.tags, { role = "app-server" })
}

resource "azurerm_storage_account" "orders" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.orders.name
  location                 = azurerm_resource_group.orders.location
  account_tier             = "Standard"
  account_replication_type = local.storage_replication_type
  min_tls_version          = "TLS1_2"
  tags                     = local.tags
}

# One block, however many containers the variable lists.
resource "azurerm_storage_container" "this" {
  for_each = var.storage_containers

  name                  = each.key
  storage_account_id    = azurerm_storage_account.orders.id
  container_access_type = each.value.access_type
}
```

### `for_each`, and why not `count`

`count` gives you a numbered list: `azurerm_storage_container.this[0]`,
`[1]`, `[2]`. The number is the identity. Delete the first item from the list
and every remaining item shifts down by one, so Terraform sees three renames and
plans to destroy and recreate all of them.

`for_each` gives you a keyed map: `azurerm_storage_container.this["orders-data"]`.
The key is the identity. Remove one entry and Terraform destroys exactly that
one; the others are not touched.

For anything with a natural name, use `for_each`. Reserve `count` for "I want N
identical copies" and for the `count = condition ? 1 : 0` on/off trick.

Inside a `for_each` block:

- `each.key` is the map key (`"orders-data"`)
- `each.value` is the map value (`{ access_type = "private" }`)

## Part 4: Write the values file

Create `environments/dev/dev.tfvars`:

```hcl
environment         = "dev"
location            = "eastus"
vnet_address_space  = ["10.10.0.0/16"]
vm_size             = "Standard_F1als_v7"
storage_name_suffix = "<suffix>"
```

Type your four characters in place of `<suffix>`. This is a file, so it needs the
literal value.

Notice what is **not** in here: no password. Secrets never go in a `.tfvars`
file, because `.tfvars` files belong in the repository. `vm_admin_password` and
`allowed_ssh_source` still come from `TF_VAR_` environment variables.

### Variable precedence

When the same variable is set in more than one place, Terraform takes the last
one on this list:

1. the `default` in the `variable` block
2. `TF_VAR_<name>` environment variables
3. `terraform.tfvars` and `*.auto.tfvars`, loaded automatically
4. `-var-file ...` on the command line, in the order given
5. `-var=...` on the command line

So a `-var` flag beats everything, and a `default` loses to everything. If a
value is not what you expect, walk that list from the bottom.

> **Why `dev.tfvars` and not `terraform.tfvars`?** A file named
> `terraform.tfvars` loads automatically, which is convenient and invisible. The
> explicit form makes the command state which values were used:
> `terraform plan -var-file dev.tfvars`. When someone asks six months
> from now "what did prod actually apply with," the answer is in the command,
> not in a filename convention.

## Part 5: Outputs

Rewrite `environments/dev/outputs.tf`:

```hcl
output "resource_group_name" {
  description = "Name of the environment resource group."
  value       = azurerm_resource_group.orders.name
}

output "vm_public_ip" {
  description = "Public IP address of the application VM."
  value       = azurerm_public_ip.app.ip_address
}

output "vm_ssh_command" {
  description = "Ready-to-paste SSH command."
  value       = "ssh ${var.vm_admin_username}@${azurerm_public_ip.app.ip_address}"
}

output "storage_account_name" {
  description = "Name of the environment storage account."
  value       = azurerm_storage_account.orders.name
}

# A "for" expression: build a new list by walking a collection.
output "container_names" {
  description = "Blob containers created in this environment."
  value       = [for name, cfg in var.storage_containers : name]
}

output "subnet_address_prefix" {
  description = "Address prefix computed for the app subnet."
  value       = one(azurerm_subnet.app.address_prefixes)
}
```

`[for name, cfg in var.storage_containers : name]` is a **for expression**. It
walks the map and produces a list of the keys. The same shape with braces
produces a map. It is the closest thing HCL has to a loop.

`one()` takes a collection with exactly one element and returns that element,
erroring if there is more than one. It is the tidy way to say "I know this list
has one item."

## Part 6: Plan and read it properly

From `environments/dev`:

```powershell
terraform fmt
terraform validate
terraform plan -var-file dev.tfvars
```

> **Note the space, not an equals sign.** Terraform's own documentation writes
> this as `-var-file=dev.tfvars`, and that form breaks in PowerShell. PowerShell
> parses the argument as a parameter name and stops at the `.`, so Terraform
> receives `-var-file=dev` and `.tfvars` as two separate arguments and reports:
>
> ```
> Error: Too many command line arguments
> ```
>
> `-var-file dev.tfvars` passes as two clean arguments and works everywhere. The
> `=` form is fine in bash, which is why the pipeline you build later uses it.

Read the summary line. You should see something close to:

```
Plan: 2 to add, 1 to change, 1 to destroy.
```

Now work out where each of those comes from, which is the point of
the lab.

**1 to destroy, and 2 to add: the storage containers.** You renamed
`azurerm_storage_container.orders_data` to
`azurerm_storage_container.this["orders-data"]` and added
`this["orders-logs"]`. Terraform sees the old address disappear and two new ones
appear. It cannot tell that one of them is the same container under a new label.

**Do not apply this yet.** Terraform would delete the container and immediately
try to create one with the same name, and that fails:

```
Error: a resource with the ID ".../containers/orders-data" already exists - to be
managed via Terraform this resource needs to be imported into the State.
```

The delete has not finished propagating when the create runs. Running `apply` a
second time succeeds, but there is no reason to destroy the container at all.

Tell state about the move instead, exactly as you did in Lab 5:

```powershell
terraform state mv 'azurerm_storage_container.orders_data' 'azurerm_storage_container.this["orders-data"]'
```

Note the single quotes. The new address contains double quotes, and single quotes
stop PowerShell from touching them.

```
Move "azurerm_storage_container.orders_data" to "azurerm_storage_container.this[\"orders-data\"]"
Successfully moved 1 object(s).
```

Now plan again:

```powershell
terraform plan -var-file dev.tfvars
```

The destroy is gone. What remains is **1 to add** for the new `orders-logs`
container, plus the tag change below. Nothing is destroyed, and the container that
already existed is simply relabelled in state.

> This is the same lesson as Lab 5, met in the wild: changing how you *address* a
> resource is not the same as changing the resource. `for_each` changed the
> address of a container you already had.

**1 to change: the VM tags.** You added `role = "app-server"` with `merge()`.
Terraform shows this as `~ tags` with the added key. Tags update in place; no
replacement.

**Everything else: silent.** Nine resources went from hardcoded literals to
computed expressions, and the plan does not mention them, because the values
they compute to are identical. That silence is what a good refactor looks like.

> If your plan wants to destroy and recreate the VM, the VNet, or the storage
> account, **stop**. Something in the computed name or region does not match what
> is deployed. Compare the plan's proposed value to what `terraform state show`
> reports and find the mismatch before applying.

```powershell
terraform apply -var-file dev.tfvars
```

Because you moved the container in state rather than letting Terraform destroy it,
this reports:

```
Apply complete! Resources: 1 added, 1 changed, 0 destroyed.
```

**Zero destroyed** is the number that matters. `terraform state list` now shows
twelve resources, including both containers:

```
azurerm_storage_container.this["orders-data"]
azurerm_storage_container.this["orders-logs"]
```

Then check the outputs:

```powershell
terraform output
terraform output vm_public_ip
terraform output -json container_names
```

`terraform output <name>` gives one value, which is how a script gets it.
`-json` gives it machine-readable, which is how a pipeline gets it.

## Part 7: Parameterize production the same way

Prod is one resource group today. Give it the same shape now, so the pattern is
already there when you add real infrastructure to it.

Create `environments/prod/variables.tf`:

```hcl
variable "org" {
  description = "Short organization prefix used in resource names."
  type        = string
  default     = "summit"
}

variable "solution" {
  description = "The solution this environment belongs to."
  type        = string
  default     = "orders"
}

variable "environment" {
  description = "Environment name."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "location" {
  description = "Azure region for every resource in this environment."
  type        = string
  default     = "eastus"
}

variable "owner" {
  description = "Team responsible for this environment."
  type        = string
  default     = "ops-team"
}
```

Create `environments/prod/prod.tfvars`:

```hcl
environment = "prod"
location    = "eastus"
```

And rewrite the resource in `environments/prod/main.tf` to use them (keep the
`terraform` and `provider` blocks as they are):

```hcl
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
```

```powershell
cd ..\prod
terraform plan -var-file prod.tfvars
```

**No changes.** Same resource, described in a portable way.

> **Notice what you just did: you copied `variables.tf` and `locals` from dev
> into prod.** Two copies of the same logic, which will drift the moment someone
> edits one of them. That duplication is the problem modules solve, and you will
> solve it shortly. Notice the annoyance now.

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
   `dev.tfvars` and `prod.tfvars` **should** be there. They hold no secrets and
   they are the record of what each environment applies with.
   There must be **no** `.tfstate` files and no `.terraform/` directory.
2. Hover over **Changes** and click the **+** to stage everything.
3. In the message box, write:

   ```
   Parameterize dev and prod with variables, locals, and tfvars
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
git commit -m "Parameterize dev and prod with variables, locals, and tfvars"
git push -u origin feature/lab06-variables
# open and merge the pull request, then:
git switch main
git pull
```

## How to verify

- [ ] `terraform plan -var-file dev.tfvars` in dev reports **No changes**
- [ ] `terraform plan -var-file prod.tfvars` in prod reports **No changes**
- [ ] `terraform state list` in dev shows `azurerm_storage_container.this["orders-data"]` and `["orders-logs"]`
- [ ] Passing an invalid `environment` produces a validation error, not an Azure error
- [ ] `terraform output container_names` returns both container names
- [ ] No password appears in any committed file

## Challenge (optional)

If you finish early:

1. Add a `cost_center` variable with a default of `"retail-ops"` and put it in
   `local.tags`. Apply, and confirm the tag appears on every resource with a
   single change.
2. Add a third container to `storage_containers` in `dev.tfvars` and plan.
   Confirm Terraform adds exactly one container and does not touch the other
   two. That is `for_each` earning its keep.
3. Change `location` in `dev.tfvars` to `westus` and run `plan` (do **not**
   apply). What does Terraform want to do, and why is a region change so
   expensive? Change it back.

## If you get stuck

| Error | What it means and what to do |
|---|---|
| `a resource with the ID ".../containers/orders-data" already exists` | You applied the `for_each` plan without running `terraform state mv` first, so Terraform destroyed the container and could not immediately recreate it under the same name. Run `apply` again to finish, or see Part 5 for the `state mv` that avoids the destroy entirely. |
| `No value for required variable` | You forgot `-var-file dev.tfvars`, or the variable is one of the `TF_VAR_` ones and this terminal does not have it. |
| `Invalid value for variable: environment must be one of...` | Your validation is working. Fix the value in `dev.tfvars`. |
| `Invalid function argument` on `cidrsubnet` | `vnet_address_space` is missing or not a list. It must be `["10.10.0.0/16"]`, with brackets. |
| Plan wants to replace the storage account | `local.storage_account_name` does not evaluate to the deployed name. Run `terraform console -var-file dev.tfvars` and print `local.storage_account_name`. Compare it with `terraform state show azurerm_storage_account.orders`. |
| Plan wants to replace the VM or VNet | A computed name or the region changed. Same technique: print the local in the console and compare. Do not apply until it matches. |
| `Reference to undeclared local value` | Locals live in a `locals { }` block, and you reference them as `local.x`, singular. The block is plural, the reference is not. |
| `Error: Duplicate variable declaration` | You added the new `variables.tf` content without deleting the old declarations. |

## Cleanup

Nothing to destroy. Deallocate the VM if you are stopping for the day.

## Congratulations!

The dev configuration no longer knows it is dev. It builds whatever environment
its variable file describes, validates the inputs before it starts, computes its
own names, and adds containers by editing a list rather than copying a block.

You also found the limit of what variables can fix: prod still has its own copy
of the same logic. Sharing that logic instead of duplicating it is the next
thing to solve.
