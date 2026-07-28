# Lab 6: Variables, Locals, Outputs, and Expressions

## Overview

Open `environments/dev/main.tf` and count the string literals. `"eastus"`
appears in seven resources. `"summit-orders-dev"` is baked into eight names.
`"Standard_F1als_v7"` and `"LRS"` are decisions somebody made once and nobody can
change without a find-and-replace.

Now imagine building `prod` by copying that file and editing every literal.
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

```powershell
cd C:\Users\Administrator\Downloads\terraform\labs\az-tf-ops-<your-username>
git switch main
git pull
git switch -c feature/lab06-variables

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

**`description` on every variable.** Not politeness. Terraform prints it when a
value is missing, and tools like `terraform-docs` build the module documentation
from it. In Lab 7 you will read someone else's module by reading exactly these
descriptions.

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
  storage_replication_type = var.environment == "prod" ? "ZRS" : "LRS"
}
```

Three techniques in eleven lines.

**String interpolation.** `"${var.org}-${var.solution}-${var.environment}"`
substitutes each expression into the string.

**A function.** `replace(local.name_prefix, "-", "")` turns
`summit-orders-dev` into `summitordersdev`. Note that a local can reference
another local.

**A conditional expression.** `condition ? value_if_true : value_if_false`. Read
it as "if the environment is prod, ZRS, otherwise LRS."

### Play with expressions before you commit them

`terraform console` gives you an interactive evaluator with your variables and
state loaded. It is the fastest way to answer "what does this function actually
return?"

```powershell
terraform console -var-file=dev.tfvars
```

(Create `dev.tfvars` first, in Part 4, if the console complains about missing
variables. Or pass `-var` flags.)

Try these:

```
> replace("summit-orders-dev", "-", "")
"summitordersdev"

> cidrsubnet("10.10.0.0/16", 8, 1)
"10.10.1.0/24"

> merge({ a = 1, b = 2 }, { b = 99, c = 3 })
{
  "a" = 1
  "b" = 99
  "c" = 3
}

> format("vm-%s-%02d", "app", 3)
"vm-app-03"

> coalesce(null, "", "fallback")
"fallback"

> upper("dev") == "DEV"
true
```

Type `exit` to leave.

| Function | What it does | Where you use it here |
|---|---|---|
| `replace` | substring substitution | stripping hyphens from a storage name |
| `cidrsubnet` | carve a subnet out of a larger range | deriving the app subnet from the VNet |
| `merge` | combine maps, right side wins | adding a per-resource tag to the standard set |
| `format` | printf-style strings | zero-padded names for numbered resources |
| `coalesce` | first non-null, non-empty value | "use the override if set, otherwise the default" |
| `contains` | is this value in that list | variable validation |
| `can` | did this expression succeed | variable validation |

## Part 3: Rewrite the resources

Now replace the literals. Here is the whole of `environments/dev/main.tf` after
the `terraform`, `provider`, and `locals` blocks:

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

Replace `<suffix>` with yours.

Notice what is **not** in here: no password. Secrets never go in a `.tfvars`
file, because `.tfvars` files belong in the repository. `vm_admin_password` and
`allowed_ssh_source` still come from `TF_VAR_` environment variables.

### Variable precedence

When the same variable is set in more than one place, Terraform takes the last
one on this list:

1. the `default` in the `variable` block
2. `TF_VAR_<name>` environment variables
3. `terraform.tfvars` and `*.auto.tfvars`, loaded automatically
4. `-var-file=...` on the command line, in the order given
5. `-var=...` on the command line

So a `-var` flag beats everything, and a `default` loses to everything. If a
value is not what you expect, walk that list from the bottom.

> **Why `dev.tfvars` and not `terraform.tfvars`?** A file named
> `terraform.tfvars` loads automatically, which is convenient and invisible. The
> explicit form makes the pipeline command in Lab 10 say out loud which values
> were used: `terraform plan -var-file=dev.tfvars`. When someone asks six months
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

```powershell
terraform fmt
terraform validate
terraform plan -var-file=dev.tfvars
```

Read the summary line. You should see something close to:

```
Plan: 2 to add, 1 to change, 1 to destroy.
```

Now work out where each of those comes from, because this is the whole point of
the lab.

**1 to destroy, and 2 to add: the storage containers.** You renamed
`azurerm_storage_container.orders_data` to
`azurerm_storage_container.this["orders-data"]` and added
`this["orders-logs"]`. Terraform sees the old address disappear and two new ones
appear. It cannot tell that one of them is the same container under a new label.

The container is empty, so this is harmless, and letting it happen teaches the
lesson. **In Lab 12 you meet the `moved` block**, which is how you tell
Terraform "this address became that address" as a line of committed code, and it
is what you would use if the container held anything.

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
terraform apply -var-file=dev.tfvars
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

Prod is one resource group today. Give it the same shape, so that when Lab 7
adds real infrastructure the pattern is already there.

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
terraform plan -var-file=prod.tfvars
```

**No changes.** Same resource, described in a portable way.

> **Notice what you just did: you copied `variables.tf` and `locals` from dev
> into prod.** Two copies of the same logic, which will drift the moment someone
> edits one of them. That is precisely the problem modules solve, and it is Lab
> 7's whole reason for existing. Feel the annoyance now so the fix lands.

## Part 8: Commit

```powershell
cd C:\Users\Administrator\Downloads\terraform\labs\az-tf-ops-<your-username>
terraform -chdir=environments/dev fmt
terraform -chdir=environments/prod fmt

git add -A
git status
```

`dev.tfvars` and `prod.tfvars` **should** appear in the staged changes. They hold
no secrets and they are the record of what each environment applies with.

```powershell
git commit -m "Parameterize dev and prod with variables, locals, and tfvars"
git push -u origin feature/lab06-variables
```

Open a pull request, merge it, pull `main`.

## How to verify

- [ ] `terraform plan -var-file=dev.tfvars` in dev reports **No changes**
- [ ] `terraform plan -var-file=prod.tfvars` in prod reports **No changes**
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
| `No value for required variable` | You forgot `-var-file=dev.tfvars`, or the variable is one of the `TF_VAR_` ones and this terminal does not have it. |
| `Invalid value for variable: environment must be one of...` | Your validation is working. Fix the value in `dev.tfvars`. |
| `Invalid function argument` on `cidrsubnet` | `vnet_address_space` is missing or not a list. It must be `["10.10.0.0/16"]`, with brackets. |
| Plan wants to replace the storage account | `local.storage_account_name` does not evaluate to the deployed name. Run `terraform console -var-file=dev.tfvars` and print `local.storage_account_name`. Compare it with `terraform state show azurerm_storage_account.orders`. |
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
of the same logic. Lab 7 sources that logic from Summit's shared modules
repository, and both environments become thin files that say what they want
rather than how to build it.
