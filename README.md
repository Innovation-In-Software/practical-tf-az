# Practical Terraform for Azure Operations Teams

[Lab environments](https://docs.google.com/spreadsheets/d/1aldG8TSXSl5oKmenfi7I8WjM2FuOt0LCdzuC5e3ZL-8/edit?usp=sharing)

Lab guide for the 3-day course.

Across the week you work as part of **Summit Retail's cloud operations team**,
taking their Orders platform from a resource group somebody clicked into
existence to a multi-environment, module-composed, secret-safe,
pipeline-delivered Terraform repository, with a legacy environment imported
along the way.

**The labs are cumulative.** From Lab 3 on, each one starts from the repository
the previous lab produced. Labs 1 and 9 add a pre-seeded environment.

## Before you start

Work through the [setup guide](labs/setup/index.md). It takes about fifteen
minutes and prevents most of the problems people hit later in the week.

- Visual Studio Code, with the **HashiCorp Terraform** and **GitHub Pull Requests** extensions
- Terraform 1.15.x (`terraform version`)
- Azure CLI, signed in with `az login`, pointed at the class subscription
- Git configured with your name and email, and access to the class GitHub organization
- A 4-character student suffix, picked in the setup guide and used all week

## Day 1: Mindset, source control, first Terraform, provisioning Azure

| Lab | What you build |
|---|---|
| [Lab 1: From click-ops to infrastructure as code](labs/lab-01-portal-vs-iac/index.md) | The same resource group two ways: clicked, then described in code |
| [Lab 2: Git and pull requests in VS Code](labs/lab-02-git-and-github/index.md) | The branch, commit, push, review, merge loop. Plus your own copy of the Orders repository |
| [Lab 3: Your first Terraform configuration](labs/lab-03-first-config/index.md) | Resource group, virtual network, subnet, and the full `init` to `apply` lifecycle |
| [Lab 4: A realistic environment](labs/lab-04-realistic-environment/index.md) | NSG, Linux VM, storage, consistent tags, and your first variable |

## Day 2 and Day 3

Published at the end of each day. Day 2 covers remote state, a
multi-environment repository, variables and expressions, shared modules, and
Azure Key Vault. Day 3 covers importing existing infrastructure, CI/CD with
GitHub Actions, troubleshooting and drift, and refactoring with `moved`.

**Pull this repository each morning** to pick them up:

> Source Control panel > the ellipses (three dots) next to **Changes** >
> **Pull**.

## Repositories you will use

| Repository | What it is |
|---|---|
| [`az-tf-ops`](https://github.com/Innovation-In-Software/az-tf-ops) | Summit's Orders platform repository. Lab 2 practices in the shared copy, then you make your own from it |
| [`az-tf-ops-modules`](https://github.com/Innovation-In-Software/az-tf-ops-modules) | Summit's shared in-house modules. You consume these from Lab 7 on. You never edit them |

## Solutions

`solutions/` holds the complete end state of each lab. Use it to catch up if you
fall behind, or to compare against your own work afterwards. Replace `<suffix>`
with yours before running anything from it.

Solutions appear alongside their labs, so `solutions/` currently covers Day 1
only.

## Conventions used in every lab

| | |
|---|---|
| Region | `eastus` |
| Terraform | `required_version = ">= 1.9"`, run on 1.15.x |
| Provider | `hashicorp/azurerm`, pinned `~> 4.0` |
| Naming | `<type>-summit-orders-<environment>`, for example `vnet-summit-orders-dev` |
| Tags | `environment`, `solution`, `owner`, `managed_by` on everything |
| Shell | PowerShell, on the Windows dev VM. Where syntax differs, the macOS and Linux form is shown too |

## If something goes wrong

Every lab ends with an **If you get stuck** table covering the errors that lab
actually produces. Check there first. The most common problem all week is
`ARM_SUBSCRIPTION_ID` not being set in the terminal you are typing in.
