# Lab 1: From Click-Ops to Infrastructure as Code

## Overview

You already know how to build things in the Azure portal. In this lab you will
do exactly that, create a resource group and a storage account by clicking, and
then open a Terraform file that describes the same result in code.

The goal is not to learn Terraform syntax yet. The goal is to feel the
difference between the two styles of work:

- In the portal you perform a **sequence of steps**. You click, you choose, you
  click again. If someone asks "how do I rebuild this exactly?" the honest
  answer is "click all of that again and hope you remember the defaults."
- In Terraform you describe the **end state** you want. You do not list the
  steps. Terraform works out the steps for you, every time, the same way.

That shift, from listing steps to describing the end state, is what "declarative"
means, and it is the idea the whole course is built on. **Infrastructure as Code
(IaC)** is simply managing infrastructure with declarative files like the one you
will read here, kept in source control.

By the end of this lab you will be able to look at a portal deployment and point
to the exact line of Terraform that produces each part of it.

> You will **not** run `terraform apply` in this lab. You will only read the
> config and run `terraform plan` so you can see how Terraform describes the same
> resources. Applying comes in Lab 3.

## What you'll need

- The [setup guide](../setup/index.md) completed.
- Access to the class Azure subscription in the portal.
- Visual Studio Code with the **HashiCorp Terraform** extension installed.
- Azure CLI signed in: run `az login` and confirm you are on the class
  subscription with `az account show`.
- The class repository cloned, from [Step 6 of the setup
  guide](../setup/index.md). This lab reads a file from it:

  ```
  C:\Users\Administrator\Downloads\repos\practical-tf-az\labs\lab-01-portal-vs-iac\main.tf
  ```

  If that folder is not on your machine, go back and do Step 6 now.

Commands are shown in **PowerShell**, which is what you have on the Windows
development VM. Where the syntax differs on macOS or Linux, both are given.

## Part 1: Build it by hand in the portal

First, the way you already know.

### Create a resource group

A **resource group (RG)** is the container Azure puts related resources in.

1. In the [Azure portal](https://portal.azure.com), use the search bar at the
   top and search for **Resource groups**. Click it in the results.
2. Click **+ Create**.
3. On the **Basics** tab:
   - **Subscription:** the class subscription.
   - **Resource group:** `rg-summit-lab1`.
   - **Region:** **East US**.
4. Click **Next: Tags**.
5. On the **Tags** tab, add these three tags. Notice that you are typing them by
   hand, and that nothing stops a teammate from spelling them differently:
   - `environment` = `lab`
   - `solution` = `orders`
   - `owner` = `ops-team`
6. Click **Review + create**, then **Create**.

### Create a storage account

1. Search for **Storage accounts** in the top search bar and click it.
2. Click **+ Create**.
3. On the **Basics** tab:
   - **Resource group:** `rg-summit-lab1` (the one you just made).
   - **Storage account name:** a globally unique name, 3 to 24 characters,
     lowercase letters and numbers only. Try `stsummitlab1` followed by a few
     random digits, for example `stsummitlab1428`. If the name is taken, the
     portal will tell you.
   - **Region:** **East US**.
   - **Primary service:** leave the default.
   - **Performance:** **Standard**.
   - **Redundancy:** **Locally-redundant storage (LRS)**.
4. Click through the remaining tabs (**Advanced**, **Networking**, **Data
   protection**, and so on) and **leave every default as is**. Notice how many
   screens of defaults you are silently accepting.
5. Click **Review + create**, then **Create**.
6. When the deployment finishes, click **Go to resource** and look at the
   **Overview** page.

Take a moment to appreciate what just happened: you made a series of choices
across several screens, and most of them were defaults you did not think about.
Nothing recorded those choices except the running resource itself.

## Part 2: Read the same result as Terraform

Now open the version that lives in a file.

First make a folder for this lab and copy the starter file into it. You work in
your own folder, never inside the class repository:

```powershell
mkdir C:\Users\Administrator\Downloads\terraform\labs\lab-01
Copy-Item C:\Users\Administrator\Downloads\repos\practical-tf-az\labs\lab-01-portal-vs-iac\main.tf C:\Users\Administrator\Downloads\terraform\labs\lab-01\
```

> **Why copy it?** In Part 3 you run `terraform init`, which downloads a provider
> several hundred megabytes in size into whatever folder you are standing in. You
> do not want that inside the class repository you pull updates into every
> morning.

1. In VS Code, choose **File > Open Folder** and open:

   ```
   C:\Users\Administrator\Downloads\terraform\labs\lab-01
   ```
2. Open `main.tf`. Because you have the HashiCorp Terraform extension, the file
   should be color-coded.
3. Read it top to bottom. It is short. It produces the same resource group and
   storage account you just built by hand.

Here is how the portal fields map to the file. Keep the portal open on one side
and `main.tf` on the other, and match each row.

| What you clicked in the portal | Where it lives in `main.tf` |
|---|---|
| Created a resource group | the `azurerm_resource_group "lab1"` block |
| Resource group **name** = `rg-summit-lab1` | `name = "rg-summit-lab1"` |
| **Region** = East US | `location = "eastus"` |
| The three **tags** | the `tags = { ... }` map |
| Created a storage account | the `azurerm_storage_account "lab1"` block |
| Storage account **name** | `name = "stsummitlab1xyz"` |
| Which **resource group** it goes in | `resource_group_name = azurerm_resource_group.lab1.name` |
| **Performance** = Standard | `account_tier = "Standard"` |
| **Redundancy** = LRS | `account_replication_type = "LRS"` |

Notice two things the file does that the portal did not:

- The storage account does not repeat the resource group name or region. It
  **refers** to them: `azurerm_resource_group.lab1.name`. Change the region in
  one place and the storage account follows. This is the first hint of why code
  scales better than clicking.
- The tags are written once and reused (`tags = azurerm_resource_group.lab1.tags`).
  There is no way for `environment` to be spelled two different ways.

> The `provider "azurerm"` block at the top and the `terraform { ... }` block
> are plumbing: they tell Terraform which provider to download and which Azure
> subscription to talk to. You will learn these properly in Lab 3. For now, just
> notice they exist.

## Part 3: Let Terraform describe the end state

You will not apply anything. You will ask Terraform to compare the file to your
subscription and tell you what it would do.

1. Right-click the `lab-01` folder in the VS Code Explorer and choose **Open in
   Integrated Terminal**. Confirm you are in the right place before you run
   anything: the prompt should end in `terraform\labs\lab-01`, not `practical-tf-az`.
2. Make sure the CLI knows your subscription (only needed once per terminal):
   ```powershell
   $env:ARM_SUBSCRIPTION_ID = (az account show --query id -o tsv)
   ```
   On macOS or Linux, use:
   ```sh
   export ARM_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
   ```
3. Initialize the working directory. This downloads the Azure provider:
   ```sh
   terraform init
   ```
4. Ask Terraform what it would create:
   ```sh
   terraform plan
   ```

Read the output. Terraform will report something like **"Plan: 2 to add, 0 to
change, 0 to destroy"** and show a `+` next to a resource group and a storage
account.

Sit with why that happens, because it surprises people. The resource group in
this file is named `rg-summit-lab1`, which is **exactly** the one you created in
the portal ten minutes ago. It is real. It exists. And Terraform still offers to
create it.

The reason is that **Terraform's picture of the world is its state file, not
Azure.** You have never run `apply` here, so there is no state, so as far as
Terraform is concerned it manages nothing at all. It is not lying to you and it
has not failed to look. It simply has no record connecting that line in your file
to that resource group in your subscription.

What it did next is the part worth noticing. It did not ask you *how* to build
anything. It read the end state you described and worked out the plan itself.

> **So what would happen if you ran `apply`?** The storage account would be
> created, because the name in the file (`stsummitlab1xyz`) is not the one you
> typed in the portal. The resource group would fail, because Azure already has
> one by that name and Terraform does not know it is yours to manage. Connecting
> existing resources to Terraform is a real and common job, and it is what Lab 9
> is about. Do not run `apply` here.

> This is the whole point of the lab. You described a result, and a tool produced
> a repeatable plan to reach it. In Lab 3 you will let it actually run.

## Reflect

Talk through these with a neighbor or the instructor:

1. If you had to build this exact environment in three different regions, which
   approach is less error-prone, and why?
2. In the portal, where is the record of the defaults you accepted? In the
   Terraform file, where is it?
3. A teammate needs to review your change before it goes live. Which of the two
   approaches can they read, comment on, and approve before anything is built?

## Cleanup

1. In the portal, search for **Resource groups**, open `rg-summit-lab1`, and
   click **Delete resource group**. Type the name to confirm. This removes both
   the resource group and the storage account inside it.
2. In VS Code, you can delete the `.terraform` directory that `terraform init`
   created to free up space. There is nothing to `destroy`, because you never
   applied.

## Congratulations!

You built infrastructure two ways: as a sequence of clicks, and as a declarative
file. You can now point to the line of Terraform behind each part of a portal
deployment, and you have seen Terraform turn a description of an end state into a
plan. Every module from here builds on that idea.

Next: [Lab 2](../lab-02-git-and-github/index.md), where you set up the workflow
every change travels through before you write any more Terraform.
