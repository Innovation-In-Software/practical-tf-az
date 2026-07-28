# Lab Setup: Before You Start

Work through this once, before Lab 1. It takes about fifteen minutes and it
prevents most of the problems people hit later in the week.

Everything here happens on the **Windows development VM** assigned to you. Sign
in over RDP or through Azure Bastion in the browser, and use **PowerShell** for
the command line examples. Where a command differs on macOS or Linux, the lab
shows both.

## What you should already have

| Thing | How to check |
|---|---|
| Windows dev VM, local administrator | you are signed in |
| Terraform 1.15.x | `terraform version` |
| Azure CLI | `az version` |
| Git | `git --version` |
| Visual Studio Code | it opens |
| VS Code: HashiCorp Terraform extension | Extensions panel shows it installed |
| VS Code: GitHub Pull Requests extension | Extensions panel shows it installed |
| An Azure subscription where you are **Owner** | see below |
| A GitHub account in the `Innovation-In-Software` organization | see below |

If any of these are missing, tell the instructor now rather than at the start of
a lab.

## Step 1: Pick your student suffix

Several Azure resource names have to be unique across **all of Azure**, not just
your subscription. Storage account names and Key Vault names are the two you
will meet this week. If two people in the class pick the same name, the second
one gets an error.

Choose a short suffix now and use the same one all week:

- 4 characters
- lowercase letters and numbers only
- something tied to you, for example your initials plus two digits

For the rest of the labs, wherever you see `<suffix>`, substitute yours.

> Example: Jamie Rivera picks `jr42`. Their storage account in Lab 4 will be
> `stsummitordersdevjr42`. Write your suffix on a sticky note. You will type it
> a lot.

## Step 2: Sign in to Azure and set your subscription

```powershell
az login
```

A browser window opens. Sign in with the account the instructor gave you.

Confirm which subscription you landed on:

```powershell
az account show --output table
```

If you have more than one subscription, set the class one explicitly:

```powershell
az account list --output table
az account set --subscription "<the class subscription name or id>"
```

### Tell Terraform which subscription to use

Version 4 of the Azure provider will not guess. It requires the subscription id,
and the cleanest way to supply it is an environment variable, so it never gets
committed to a file.

```powershell
$env:ARM_SUBSCRIPTION_ID = (az account show --query id -o tsv)
```

That lasts only for the current PowerShell window. To set it once for your whole
user profile so every new terminal has it:

```powershell
[System.Environment]::SetEnvironmentVariable(
  "ARM_SUBSCRIPTION_ID",
  (az account show --query id -o tsv),
  "User"
)
```

Close and reopen your terminal, then check it stuck:

```powershell
$env:ARM_SUBSCRIPTION_ID
```

On macOS or Linux the equivalent is:

```sh
export ARM_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
```

> **This is the single most common cause of a failed `terraform plan` this
> week.** If you ever see `subscription_id is a required provider property`, you
> are in a terminal that does not have the variable set.

### Confirm the resource providers are registered

Your subscription needs four Azure resource providers turned on. They usually
are, but checking takes five seconds:

```powershell
az provider show --namespace Microsoft.Compute  --query registrationState -o tsv
az provider show --namespace Microsoft.Network  --query registrationState -o tsv
az provider show --namespace Microsoft.Storage  --query registrationState -o tsv
az provider show --namespace Microsoft.KeyVault --query registrationState -o tsv
```

Each should print `Registered`. If one says `NotRegistered`, register it:

```powershell
az provider register --namespace Microsoft.KeyVault
```

## Step 3: Set your Git identity

Git stamps your name and email on every commit. Set them once:

```powershell
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

Use the same email that is on your GitHub account, so your commits are linked to
your profile.

Two settings that save trouble on Windows:

```powershell
git config --global init.defaultBranch main
git config --global core.autocrlf true
```

## Step 4: Sign in to GitHub from VS Code

1. Open VS Code.
2. Click the **Accounts** icon at the bottom of the left activity bar (the
   person outline).
3. Choose **Sign in with GitHub**, and complete the browser prompt.
4. Back in VS Code, open the **Extensions** panel and confirm both extensions
   are installed and enabled:
   - **HashiCorp Terraform**
   - **GitHub Pull Requests**

You should now see a **GitHub** icon in the activity bar. That is where pull
requests show up in Lab 2.

## Step 5: Clone the class repository

The lab guide, the starter files, and the instructor solutions all live in one
repository. Clone it now, because **Lab 1 opens a file from it**.

First make the folder it goes in:

```powershell
mkdir C:\Users\Administrator\Downloads\repos
```

Then clone:

1. Open a new **Visual Studio Code** window.
2. Click **Clone Repository** and paste:

   ```
   https://github.com/Innovation-In-Software/practical-tf-az
   ```

3. Press Enter. In the pop-up window, browse to
   `C:\Users\Administrator\Downloads\repos`.
4. Click **Select as repository destination**.
5. When prompted to open the cloned repository, choose **Open**.
6. Click the third icon in the left toolbar for **Source Control**. Next to
   **Changes**, click the ellipses (three dots) and choose **Pull**.

The command line equivalent, for reference:

```powershell
mkdir C:\Users\Administrator\Downloads\repos
cd C:\Users\Administrator\Downloads\repos
git clone https://github.com/Innovation-In-Software/practical-tf-az.git
```

You now have:

```
C:\Users\Administrator\Downloads\repos\practical-tf-az\
  README.md          the lab index
  labs\              one folder per lab, including Lab 1's starter main.tf
  solutions\         the finished state of each lab, if you fall behind
```

> **Pull this again each morning.** Use the same Source Control > ellipses >
> **Pull** step. If a lab gets a correction during the week, that is how you
> pick it up.

## Step 6: Know the two Summit repositories

Separately from the class repository above, Summit Retail's platform lives in
two public repositories in the `Innovation-In-Software` GitHub organization:

| Repository | What it is | What you do with it |
|---|---|---|
| [`az-tf-ops`](https://github.com/Innovation-In-Software/az-tf-ops) | The Orders platform working repository | Lab 2: branch, commit, and open a pull request against the shared copy. Then make your **own** copy from it, which you use for Labs 3 to 12. |
| [`az-tf-ops-modules`](https://github.com/Innovation-In-Software/az-tf-ops-modules) | Summit's shared in-house Terraform modules | Lab 7 onward: you consume these. You never edit them. |

Both are public, so you can read and clone them without any extra access. You
also have **write** access to `az-tf-ops` so you can push a branch and open a
pull request in Lab 2.

## Step 7: Make your working folder

You will use **two** locations all week, and it is worth being clear about which
is which:

| Folder | What lives there | You... |
|---|---|---|
| `C:\Users\Administrator\Downloads\repos\practical-tf-az` | The class repository you just cloned: lab instructions, starter files, solutions | **read** from it |
| `C:\Users\Administrator\Downloads\terraform\labs` | Everything you build this week | **write** here |

Make the working folder now:

```powershell
mkdir C:\Users\Administrator\Downloads\terraform\labs
cd C:\Users\Administrator\Downloads\terraform\labs
```

Both are under your own user profile, so you own them and nothing needs
administrator rights.

### How the working folder fills up

**Never run Terraform inside the class repository.** `terraform init` downloads
a provider that is hundreds of megabytes, and it would land in a folder you
have to `git pull` every morning. Copy what you need out of it and work in
`terraform\labs`.

Each lab tells you which folder to be in. By the end of the week you will have:

```
C:\Users\Administrator\Downloads\terraform\labs\
  lab-01\                      Lab 1: a copy of the starter main.tf
  az-tf-ops\                   Lab 2: the shared practice repository
  az-tf-ops-<your-username>\   Labs 3 to 12: your own repository. This is the
                               one that matters. Every lab from 3 on adds to it
  broken\                      Lab 11: a throwaway sandbox
```

> **Labs 3 to 12 are cumulative and all happen in one repository.** They are not
> twelve separate folders. Lab 4 builds on what Lab 3 applied, Lab 5 moves that
> state to Azure Storage, and Lab 12 refactors what you built in Labs 3 to 6.
> The standalone folders above are the exceptions: Lab 1 before you have a
> repository, and Lab 11's deliberately broken sandbox.

## Quick reference: values you will reuse all week

| Value | What to use |
|---|---|
| Azure region | `eastus` |
| Solution name | `orders` |
| Environments | `dev`, `prod` |
| Your suffix | the 4 characters you picked in Step 1 |
| Terraform version | 1.15.x (configs require `>= 1.9`) |
| Azure provider | `hashicorp/azurerm`, pinned `~> 4.0` |
| VM admin username | `azureuser` |

## Naming convention

Summit's house pattern is `<type>-<solution>-<environment>`:

- `rg-summit-orders-dev` (resource group)
- `vnet-summit-orders-dev` (virtual network)
- `nsg-summit-orders-dev` (network security group)
- `vm-summit-orders-dev` (virtual machine)

Storage accounts and Key Vaults cannot use hyphens or must be globally unique,
so they get the squashed form plus your suffix:

- `stsummitordersdev<suffix>` (storage account: lowercase and digits only, 3-24 characters)
- `kv-summit-dev-<suffix>` (Key Vault: 3-24 characters)

Consistency here is not cosmetic. In Lab 6 you generate these names from a
single pattern, and in Lab 11 the convention is what lets you spot the resource
somebody created by hand.

## If something goes wrong

| Symptom | Usual cause |
|---|---|
| `subscription_id is a required provider property` | `ARM_SUBSCRIPTION_ID` is not set in this terminal (Step 2) |
| `building account: unable to obtain authorization token` | your `az login` session expired. Run `az login` again |
| `StorageAccountAlreadyTaken` | someone else has that global name. Change your suffix |
| `AuthorizationFailed` | you are pointed at the wrong subscription. Run `az account show` |
| `terraform: command not found` | open a new terminal so it picks up the PATH |
| VS Code shows no colors in a `.tf` file | the HashiCorp Terraform extension is not enabled |

## You're ready

Head to [Lab 1](../lab-01-portal-vs-iac/index.md).
