# Lab 11: Troubleshooting and Drift

## Overview

Standing infrastructure up is day one. Everything after that is day two, and day
two looks like this:

- A configuration you did not write fails with an error you have not seen
- Somebody changed something in the portal on Friday and did not tell anyone
- Monday's `plan` wants to undo it, and you have to decide whether it should

This lab rehearses both, on purpose, in a room where it does not matter.

Part 1 is a broken configuration with four faults, one from each layer of the
stack. Part 2 is drift: you will change Summit's dev environment through the
portal, exactly the way a colleague in a hurry would, and then work out what
happened and what to do about it.

## Objectives

By the end of this lab you can:

- Tell an HCL error, a Terraform error, a provider error, and an Azure API error
  apart, and know where to look for each
- Work a fault to ground rather than guessing
- Use `TF_LOG` when the error is not enough, and know when not to
- Detect out-of-band changes with `terraform plan` and `-refresh-only`
- Decide, for a given piece of drift, whether to revert reality or update the
  configuration
- Resolve drift through the pipeline rather than from your laptop

## What you'll need

- Your repository with Lab 10 merged, and the pipeline working
- Both environments applied
- The `broken/` folder that ships with this lab

```powershell
cd C:\labs\az-tf-ops-<your-username>
git switch main
git pull
```

If your dev VM is deallocated, start it. Drift detection reads live state:

```powershell
az vm start -g rg-summit-orders-dev -n vm-summit-orders-dev
```

---

# Part 1: Reading errors

## Set up the sandbox

Copy the `broken/` folder out of the lab materials to somewhere outside your
repository, so you do not commit it:

```powershell
mkdir C:\labs\broken
Copy-Item <path-to-lab-materials>\lab-11-troubleshooting-drift\broken\main.tf C:\labs\broken\
cd C:\labs\broken
```

Set your suffix and initialize:

```powershell
$env:TF_VAR_name_suffix = "<suffix>"
terraform init
```

> **You will never `apply` this configuration.** Everything in Part 1 is
> `validate` and `plan`. There is nothing to clean up afterwards.

## The method

Before you look at anything, agree on the method. Under pressure people skim for
red text and start changing things. Do this instead:

1. **Read the whole error.** All of it. The useful line is often the third one.
2. **Note which layer it came from.** The four layers are below, and they tell
   you which tool can help.
3. **Fix exactly one thing.**
4. **Rerun.** `validate` if it was a syntax or reference problem, `plan` if it
   needs Azure.
5. **Repeat.** Errors hide behind each other: Terraform stops at the first
   parse failure and cannot see the rest of the file.

### The four layers

| Layer | Who is complaining | How to recognize it | What helps |
|---|---|---|---|
| **HCL syntax** | The parser | "Invalid block definition", "Argument or block definition required", points at a character | Read the line and the one above it |
| **Terraform** | Terraform core | "Reference to undeclared resource", "Unsupported argument", "Invalid value for variable" | The configuration itself, and the provider docs |
| **Provider** | The `azurerm` plugin | Named a resource type, mentions an argument, arrives before any API call | Provider documentation **for your major version** |
| **Azure API** | Azure | An Azure error code (`ResourceGroupNotFound`, `StorageAccountAlreadyTaken`), an HTTP status, a request id | The Azure portal, `az`, and Azure documentation |

That last row is the important distinction. **If the error has an Azure error
code in it, your HCL is fine.** You are being told about the state of the world,
not about your file, and no amount of editing the configuration will help until
you understand what Azure is objecting to.

## Fault 1: the parser

```powershell
terraform validate
```

```
Error: Invalid block definition

  on main.tf line 50, in resource "azurerm_resource_group" "sbx":
  50:   name "rg-summit-sandbox"
  51:   location = var.location

A block definition must have block content delimited by "{" and "}",
starting on the same line as the block header.
```

Read that literally and it makes sense. The parser saw `name` followed by a
quoted string, which is the shape of a **block header** (`resource "type" "name" {`),
so it went looking for an opening brace and found `location` instead.

It is a missing `=`. Fix it:

```hcl
  name     = "rg-summit-sandbox"
```

**Note that the parser found exactly one error.** It could not get past line 50,
so it has no opinion yet about the rest of the file. This is normal, and it is
why "there is only one error" is never a safe conclusion after a syntax failure.

> **`terraform fmt` catches this too, and faster.** A file that will not format
> will not parse. Running `fmt` before `validate` is a cheap first check.

```powershell
terraform validate
```

## Fault 2: Terraform core

```
Error: Reference to undeclared resource

  on main.tf line 63, in resource "azurerm_storage_account" "sbx":
  63:   resource_group_name      = azurerm_resource_group.sandbox.name

A managed resource "azurerm_resource_group" "sandbox" has not been declared in
the root module.

Error: Reference to undeclared resource

  on main.tf line 64, in resource "azurerm_storage_account" "sbx":
  64:   location                 = azurerm_resource_group.sandbox.location

...
```

**Three errors this time, not one.** The file parses now, so Terraform got far
enough to build the whole reference graph and report every broken reference at
once. That is a useful signal in itself: once you are past syntax errors,
Terraform stops giving up after the first problem.

All three references point at `azurerm_resource_group.sandbox`. The block is
called `sbx`. Somebody renamed the resource and updated the block but not the
references to it.

Fix all three occurrences: `sandbox` becomes `sbx`.

```powershell
terraform validate
```

## Fault 3: the provider

```
Error: Unsupported argument

  on main.tf line 68, in resource "azurerm_storage_account" "sbx":
  68:   enable_https_traffic_only = true

An argument named "enable_https_traffic_only" is not expected here.
```

Note that this error only appeared **after** you fixed the reference problem.
Terraform checks the configuration against the provider's schema late, once
everything else resolves. Errors genuinely do hide behind each other.

This is the most common real-world Terraform error and the least obvious,
because **the argument is not made up**. It was correct for years. Version 4 of
the `azurerm` provider renamed it to `https_traffic_only_enabled`.

Whoever wrote this copied a blog post written against version 3.

The habit that saves you: when you look up an argument, check the version
selector at the top left of the provider documentation page and set it to the
major version you have pinned. The registry defaults to the latest, and Google
sends you to whatever ranks well, which is usually three years old.

Fix it:

```hcl
  https_traffic_only_enabled = true
```

```powershell
terraform validate
```

**Success! The configuration is valid.**

Notice what that sentence does and does not mean. Your file is internally
consistent. Nothing has been checked against Azure.

## Fault 4: Azure

```powershell
terraform plan
```

```
Error: Resource Group "rg-summit-shared-services" was not found

  with data.azurerm_resource_group.shared,
  on main.tf line 45, in data "azurerm_resource_group" "shared":
  45: data "azurerm_resource_group" "shared" {
```

Your HCL is valid. Your reference is valid. The argument exists. Azure is
telling you the thing you asked for is not there.

That distinction changes what you do next. Nothing in your editor will fix this.
Go and look at reality:

```powershell
az group list --query "[].name" -o table
```

There is no `rg-summit-shared-services` in your subscription. Either it was
never created, or it lives in a subscription you are not pointed at, or the name
is wrong.

For this exercise, point it at a resource group that does exist:

```hcl
data "azurerm_resource_group" "shared" {
  name = "rg-summit-tfstate"
}
```

```powershell
terraform plan
```

```
Plan: 2 to add, 0 to change, 0 to destroy.
```

Four faults, four layers, one at a time. **Do not apply.** You are done with
this folder:

```powershell
cd C:\labs
Remove-Item -Recurse -Force C:\labs\broken
```

## When the error is not enough: `TF_LOG`

Occasionally an error tells you nothing useful, usually because a provider is
misbehaving or an API call fails in a way the provider does not surface well.
Then you turn the logs up.

```powershell
$env:TF_LOG = "DEBUG"
$env:TF_LOG_PATH = "C:\labs\terraform-debug.log"
terraform plan
```

Then turn it straight back off, because everything is slower and noisier with it
on:

```powershell
Remove-Item Env:\TF_LOG
Remove-Item Env:\TF_LOG_PATH
```

| Level | What you get |
|---|---|
| `ERROR` | errors only |
| `WARN` | errors and warnings |
| `INFO` | high-level operations |
| `DEBUG` | every provider call, including HTTP requests and responses |
| `TRACE` | everything, including Terraform's internals. Enormous |

`DEBUG` is the useful one. Open the log and search for `azurerm:` or for an HTTP
status code. You will find the actual request and response, which is how you
tell "the provider sent the wrong thing" from "Azure rejected the right thing."

Two warnings:

- **Logs can contain secrets.** Request bodies include what you sent, which may
  include a password. Never attach a raw debug log to a public issue without
  reading it first.
- **`TRACE` is rarely what you want.** A single plan produces tens of megabytes.
  Reach for it when a HashiCorp maintainer asks you to.

---

# Part 2: Drift

## What drift is

**Drift** is any difference between what your configuration says and what is
actually deployed, caused by something other than Terraform. Somebody clicked in
the portal. An automated policy tightened a setting. An incident got fixed at
2am and nobody wrote it down.

Drift is not a bug in Terraform. It is a fact about operating a shared cloud,
and the job is to notice it, understand it, and decide what to do.

## Create some, the way it really happens

You are on call. A developer says they cannot reach the dev VM on port 8080. It
is 4:50pm on a Friday. You open the portal.

### The Friday fix

1. In the portal, open `nsg-summit-orders-dev`.
2. **Inbound security rules** > **+ Add**.
3. Fill in:
   - **Source:** Any
   - **Source port ranges:** `*`
   - **Destination:** Any
   - **Service:** Custom
   - **Destination port ranges:** `8080`
   - **Protocol:** TCP
   - **Action:** Allow
   - **Priority:** `200`
   - **Name:** `AllowAppPortTemp`
4. **Add**.

<!-- screenshot: portal adding an inbound NSG rule by hand -> images/portal-nsg-rule.png -->

### The other one

Somebody in finance needs a ticket reference on the resource group.

5. Open `rg-summit-orders-dev` > **Tags**.
6. Add `ticket` = `INC-4471`. **Apply**.

<!-- screenshot: portal tags blade with the added ticket tag -> images/portal-tag.png -->

Both changes are reasonable. Neither is in code. **This is the single most
common way a Terraform repository stops being the truth.**

## Detect it

Monday morning:

```powershell
cd C:\labs\az-tf-ops-<your-username>\environments\dev
$env:TF_VAR_allowed_ssh_source = "$(Invoke-RestMethod https://api.ipify.org)/32"
terraform plan -var-file=dev.tfvars
```

```
Note: Objects have changed outside of Terraform

Terraform detected the following changes made outside of Terraform since the
last "terraform apply" which may have affected this plan:

  # azurerm_resource_group.orders has been changed
  ~ resource "azurerm_resource_group" "orders" {
      ~ tags = {
          + "ticket" = "INC-4471"
        }
    }

Terraform will perform the following actions:

  # azurerm_resource_group.orders will be updated in-place
  ~ resource "azurerm_resource_group" "orders" {
      ~ tags = {
          - "ticket" = "INC-4471" -> null
        }
    }

Plan: 0 to add, 1 to change, 0 to destroy.
```

Read the two halves. They are different things and people confuse them
constantly.

**"Objects have changed outside of Terraform"** is the report. This is what
somebody did. Terraform noticed during refresh.

**"Terraform will perform the following actions"** is the proposal. This is what
Terraform intends to do about it, which by default is **put it back**. Terraform
does not know the tag was deliberate; the configuration is the definition of
correct, and the tag is not in the configuration.

That behavior is what you want, and it is also how a well-meaning colleague's
change quietly disappears at 9am on Monday.

### Where is the NSG rule?

You may notice the NSG rule is not in the plan, or it is, depending on how the
portal wrote it. Check directly:

```powershell
az network nsg rule list `
  --nsg-name nsg-summit-orders-dev `
  --resource-group rg-summit-orders-dev `
  --query "[].{name:name, port:destinationPortRange, priority:priority}" -o table
```

```
Name               Port    Priority
-----------------  ------  ----------
AllowSSHFromAdmin  22      100
AllowAppPortTemp   8080    200
```

The rule exists in Azure. Whether `plan` proposes removing it depends on how
your NSG rules are declared. Yours are separate `azurerm_network_security_rule`
resources, and Terraform only manages the ones you declared: it does not know
`AllowAppPortTemp` exists, so it leaves it alone.

**That is worth sitting with.** A clean `terraform plan` does not mean nothing
was changed. It means nothing Terraform manages was changed. An entire rule
opening port 8080 to the internet can sit in a subnet indefinitely and never
appear in a plan.

This is the honest limitation of drift detection: **Terraform detects drift in
what it manages, not drift in your subscription.** Catching the rest needs Azure
Policy, `az` audits, or Defender for Cloud, and it belongs on your list of
things to add after this course.

## Investigate with `-refresh-only`

Before deciding, you want the facts without a proposal attached.

```powershell
terraform plan -refresh-only -var-file=dev.tfvars
```

This asks Azure what everything looks like now and reports the differences,
**without proposing any change to fix them**. It is the read-only version of
drift detection, and it is the right first command when you do not yet know what
you are dealing with.

Use it when:

- You want to know what changed before deciding anything
- You are on a system where an accidental `apply` would be serious
- You want to update state to match reality without touching infrastructure
  (`terraform apply -refresh-only`, which writes the refreshed state and changes
  nothing in Azure)

Compare the three:

| Command | Reads Azure | Proposes changes | Changes Azure |
|---|---|---|---|
| `terraform plan -refresh-only` | yes | no | no |
| `terraform plan` | yes | yes | no |
| `terraform apply` | yes | yes | **yes** |

## Decide

Two pieces of drift, two different correct answers. This is a judgment call, not
a command.

Ask: **was the change legitimate, and should it be permanent?**

| | The `ticket` tag | The port 8080 rule |
|---|---|---|
| Legitimate? | Yes, finance asked for it | It was a workaround at 4:50pm on a Friday |
| Should it persist? | Yes | No. It allows 8080 from **anywhere** |
| Answer | **Update the configuration** to match reality | **Remove it**, and if 8080 is genuinely needed, add it properly |
| How | Add the tag to `local.tags`, in a pull request | Delete the rule, in a pull request |

Neither answer is "run `terraform apply` from your laptop and move on."

> The most dangerous instinct here is treating drift as a nuisance to be flattened.
> Terraform reverting an out-of-band change is not automatically correct; it is
> just the default. Somebody made that change for a reason, and finding out what
> the reason was takes a conversation, not a command.

## Resolve, through the pipeline

You have a pipeline. Use it.

```powershell
cd C:\labs\az-tf-ops-<your-username>
git switch -c fix/reconcile-dev-drift
```

### Accept the tag

In `environments/dev/main.tf`, add it to `locals`:

```hcl
locals {
  ...
  tags = {
    environment = var.environment
    solution    = var.solution
    owner       = var.owner
    managed_by  = "terraform"
    cost_center = "retail-ops"
    ticket      = "INC-4471"
  }
}
```

### Remove the rogue rule

Terraform will not remove a rule it does not manage. Two options:

**Option A, the quick one:** delete it with the CLI, and note that this is
itself an out-of-band change, which is a little ironic.

```powershell
az network nsg rule delete `
  --nsg-name nsg-summit-orders-dev `
  --resource-group rg-summit-orders-dev `
  --name AllowAppPortTemp
```

**Option B, the one that scales:** bring it under management first, then delete
it in code. Add an `import` block for it (Lab 9), let the pipeline import it,
then remove the resource block in a second pull request so Terraform deletes it.
Slower, and every step is recorded and reviewed.

For the lab, use Option A, and understand why Option B exists. On a production
NSG with fifteen hand-added rules, Option B is how you get control back without
guessing which ones matter.

### Propose it

```powershell
terraform -chdir=environments/dev fmt
git add environments/dev/main.tf
git commit -m "Accept INC-4471 tag from portal change, drop temporary 8080 rule"
git push -u origin fix/reconcile-dev-drift
```

Open a pull request. Read the plan comment: it should show the resource group
tag going **in**, not out, because the configuration now agrees with reality.

Write a description a colleague can act on:

```
Two out-of-band changes were made to dev on Friday.

- ticket=INC-4471 tag on the resource group. Requested by finance,
  legitimate, so it is now in code.
- AllowAppPortTemp on port 8080 from Any. Added during an incident.
  Removed: it allowed 8080 from the whole internet. If the app genuinely
  needs 8080, open a ticket and we will add it scoped to the load balancer.
```

Get it reviewed, merge, and watch the apply. Then:

```powershell
git switch main
git pull
cd environments\dev
terraform plan -var-file=dev.tfvars
```

**No changes.** Reality and configuration agree again.

## Catching drift before it surprises you

You had to go looking. Better teams do not.

The standard pattern is a scheduled workflow that runs `plan` nightly and shouts
if it is not clean. You have everything you need to build it:

```yaml
on:
  schedule:
    - cron: '0 6 * * 1-5'   # 06:00 UTC, weekdays
  workflow_dispatch:
```

with a `plan -detailed-exitcode` step. That flag returns:

| Exit code | Meaning |
|---|---|
| `0` | no changes |
| `1` | error |
| `2` | changes present |

so a non-zero exit becomes a failed job, and a failed scheduled job becomes a
notification. Drift found on Tuesday morning by a robot is an inconvenience.
Drift found in December during an outage is an incident.

Adding this is the optional challenge below.

## How to verify

- [ ] `terraform plan` on the fixed sandbox reached `2 to add` with no errors
- [ ] You can name which layer each of the four faults came from
- [ ] You detected both portal changes, one through `plan` and one through `az`
- [ ] `terraform plan -refresh-only` reported the drift without proposing a fix
- [ ] Both pieces of drift were resolved through a reviewed pull request
- [ ] `terraform plan -var-file=dev.tfvars` in dev reports **No changes**

## Challenge (optional)

1. Add `.github/workflows/drift.yml`: a scheduled job that runs
   `terraform plan -detailed-exitcode` against `environments/dev` and fails when
   the exit code is `2`.
2. Introduce drift in the portal, run the workflow manually with
   **Run workflow**, and confirm it goes red.
3. Harder: on failure, have it open a GitHub issue with the plan output. Look at
   `actions/github-script` and `github.rest.issues.create`.

## If you get stuck

| Symptom | What to do |
|---|---|
| Fixing one error reveals another | Expected. Terraform stops at the first parse failure. Keep going. |
| `Unsupported argument` for something that "definitely exists" | Check the provider documentation at **version 4**, not the latest or a search result. Arguments get renamed between majors. |
| An Azure error code you do not recognize | Search the exact code. It is Azure's vocabulary, not Terraform's, and the Azure documentation is where the answer is. |
| `plan` shows no drift but you changed something in the portal | You changed something Terraform does not manage, or a read-only attribute. Confirm with `az`. |
| `plan` wants to destroy something after a portal change | Somebody changed an immutable attribute. Do not apply. Work out what changed first. |
| `-refresh-only` also shows nothing | Terraform is not tracking that attribute at all. Some Azure properties are not exposed by the provider. |
| The pipeline plan differs from your local plan | Different variables. The pipeline uses `dev.tfvars` plus its own `TF_VAR_` secrets; confirm your shell has the same values. |
| `TF_LOG` produces nothing | You set it in a different terminal than the one running Terraform. |

## Cleanup

Keep everything. Lab 12 is the last lab and handles teardown.

## Congratulations!

You worked four faults to ground by layer instead of by guesswork, and you
handled real drift the way it should be handled: notice it, understand it, judge
each change on its merits, and fix it through the same reviewed pipeline as
everything else.

You also found the limit of drift detection, which is more useful than knowing
the commands. Terraform tells you about what it manages. Everything else in the
subscription is still your problem.

Lab 12 closes the loop: the dev environment is still the hand-written
configuration from Day 1, and there is a way to modernize it without destroying
anything.
