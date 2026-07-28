# Lab 10: CI/CD with GitHub Actions

## Overview

Every `terraform apply` this week ran from your VM, as you, with your
subscription rights, and nobody watched. That works for a class. It does not
work for a team, because:

- The person applying is the person reviewing
- Nothing records what was applied, or from which commit
- Whoever applies needs standing write access to production
- "It worked on my machine" applies to infrastructure too

Summit's target workflow is the one every mature team converges on: **propose a
change in a pull request, see the plan in the pull request, and let the merge
apply it.** Nobody runs `apply` by hand.

In this lab you build that. By the end, your repository will physically refuse
to merge a change to `environments/dev` until a human has approved it and
Terraform has successfully planned it.

## Objectives

By the end of this lab you can:

- Read a GitHub Actions workflow and identify its triggers, jobs, and steps
- Create a service principal and authenticate a pipeline to Azure with it
- Store credentials as GitHub Actions secrets and reference them safely
- Run `fmt`, `validate`, and `plan` on every pull request
- Post plan output as a pull request comment for review
- Apply automatically on merge to `main`
- Protect `main` with a required review and a required status check

## What you'll need

- Your repository with Lab 9 merged, and **public** (check
  Settings > General > Danger Zone)
- A neighbor to review your pull request. GitHub does not let you approve your
  own.
- `az login` current

```powershell
cd C:\Users\Administrator\Downloads\terraform\labs\az-tf-ops-<your-username>
git switch main
git pull
git switch -c feature/lab10-github-actions
```

## Part 1: Create the pipeline's identity

A **service principal (SP)** is an identity for software. Your pipeline
authenticates as one instead of as you, so it keeps working when you leave, and
its permissions can be granted and revoked independently of yours.

```powershell
.\scripts\create-service-principal.ps1 -Name <your-github-username> -Suffix <suffix>
```

The script does three things:

1. Creates the app registration and service principal
2. Grants it **Contributor** at subscription scope, so it can manage resources
   and read the state storage account's keys
3. Grants it **Key Vault Secrets User** on both Orders vaults, so
   `data.azurerm_key_vault_secret` works in the pipeline

That third step is the bootstrapping problem from Lab 8, resolved. The pipeline
could not have granted itself access to the vault; something outside the
pipeline had to make the introduction. **This one manual grant is the root of
trust for everything the pipeline does afterwards.**

The script prints four values and ends with a warning: the client secret is
displayed **once**. Azure stores a hash. Copy all four now.

> **Contributor at subscription scope is broader than production deserves.** We
> use it because one credential then covers every lab. A real pipeline gets a
> role assignment scoped to the resource groups it manages, and separate
> principals for dev and prod so a dev pipeline compromise cannot reach
> production.

## Part 2: Store the credentials as GitHub secrets

Go to your repository on GitHub:
**Settings** > **Secrets and variables** > **Actions** > **New repository
secret**.

Add five secrets:

| Name | Value |
|---|---|
| `AZURE_CLIENT_ID` | from the script |
| `AZURE_CLIENT_SECRET` | from the script |
| `AZURE_TENANT_ID` | from the script |
| `AZURE_SUBSCRIPTION_ID` | from the script |
| `TF_VAR_ALLOWED_SSH_SOURCE` | your public IP with `/32`, from `Invoke-RestMethod https://api.ipify.org` |

<!-- screenshot: GitHub Actions secrets page with the five secrets listed -> images/gh-secrets.png -->

Two things about Actions secrets:

- **They are write-only.** Once saved, nobody, including you, can read the value
  back through the UI. You can only replace it.
- **GitHub masks them in logs.** If a secret's value appears in output, it is
  replaced with `***`. Useful, not a substitute for care: masking works on exact
  matches, so a value that gets base64 encoded or split across lines slips
  through.

That last secret is why `allowed_ssh_source` never went into `dev.tfvars`. Your
repository is public, and your home IP address in a public repository is
information you did not mean to publish.

## Part 3: Anatomy of a workflow

Create `.github/workflows/terraform.yml`. Build it in pieces so each part means
something.

### Triggers

```yaml
name: Terraform

on:
  pull_request:
    paths:
      - 'environments/dev/**'
      - '.github/workflows/terraform.yml'
  push:
    branches:
      - main
    paths:
      - 'environments/dev/**'
      - '.github/workflows/terraform.yml'
  workflow_dispatch:
```

`on:` is when the workflow runs.

- `pull_request` fires when a PR is opened or updated. This is where `plan`
  belongs.
- `push` to `main` fires when a PR merges. This is where `apply` belongs.
- `workflow_dispatch` adds a manual **Run workflow** button, useful when
  something needs a nudge.

`paths:` keeps the workflow from running on README edits. It also means a change
to `environments/prod` does not trigger the dev pipeline, which matters once you
add a second workflow.

### Permissions and concurrency

```yaml
permissions:
  contents: read
  pull-requests: write

concurrency:
  group: terraform-orders-dev
  cancel-in-progress: false
```

`permissions` scopes the automatic `GITHUB_TOKEN`. Default is broad; declaring
what you need is least privilege applied to your own pipeline. This one reads
code and writes PR comments. It does not need to push commits, so it cannot.

`concurrency` allows one run at a time in this group. Without it, two merges
seconds apart both try to `apply`, and the second one fails on the state lock
you set up in Lab 5. `cancel-in-progress: false` matters: cancelling a running
`apply` is how you get a stuck lock and a half-built environment.

### Environment variables

```yaml
env:
  TF_VERSION: '1.15.0'
  WORKING_DIR: environments/dev
  VAR_FILE: dev.tfvars

  ARM_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
  ARM_CLIENT_SECRET: ${{ secrets.AZURE_CLIENT_SECRET }}
  ARM_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
  ARM_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

  TF_VAR_allowed_ssh_source: ${{ secrets.TF_VAR_ALLOWED_SSH_SOURCE }}
```

The `ARM_*` names are what the `azurerm` provider looks for. Set them and
Terraform authenticates as the service principal with no further configuration,
including for the state backend.

`TF_VAR_allowed_ssh_source` is the same mechanism you used from your own shell
in Lab 4. Terraform does not care whether a `TF_VAR_` variable came from your
terminal or a runner.

`WORKING_DIR` is how one repository serves several environments. A prod workflow
is this file with `environments/prod` and `prod.tfvars`, which is the payoff of
the Lab 5 directory layout.

### The plan job

```yaml
jobs:
  terraform-plan:
    name: terraform-plan
    if: github.event_name == 'pull_request' || github.event_name == 'workflow_dispatch'
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: ${{ env.WORKING_DIR }}

    steps:
      - name: Check out the repository
        uses: actions/checkout@v4

      - name: Sign in to Azure
        uses: azure/login@v2
        with:
          creds: |
            {
              "clientId": "${{ secrets.AZURE_CLIENT_ID }}",
              "clientSecret": "${{ secrets.AZURE_CLIENT_SECRET }}",
              "tenantId": "${{ secrets.AZURE_TENANT_ID }}",
              "subscriptionId": "${{ secrets.AZURE_SUBSCRIPTION_ID }}"
            }

      - name: Install Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Check formatting
        run: terraform fmt -check -recursive

      - name: Initialize
        run: terraform init -input=false

      - name: Validate
        run: terraform validate -no-color

      - name: Plan
        id: plan
        continue-on-error: true
        run: |
          set -o pipefail
          terraform plan -no-color -input=false \
            -var-file="${{ env.VAR_FILE }}" \
            -out=tfplan 2>&1 | tee plan.txt
```

Worth pausing on:

**`runs-on: ubuntu-latest`** is a fresh Linux virtual machine, created for this
run and destroyed after. Nothing persists. That is why every job starts with
`checkout` and `init`.

**`uses:` versus `run:`.** `uses:` pulls in a reusable action from the
marketplace. `run:` executes a shell command. Pin actions to a major version
(`@v4`) rather than `@main`, for the same reason you pin module versions.

**`-input=false`** everywhere. There is no terminal to answer a prompt. Without
it, a missing variable hangs the job until it times out.

**`fmt -check`** fails the build on unformatted code. It seems petty until it
ends every whitespace argument in code review permanently.

**`continue-on-error: true` on the plan.** A failed plan should still be posted
to the pull request, where somebody can read the error. A later step fails the
job so the check is genuinely red.

### Posting the plan to the pull request

This is the step that makes the whole thing worth building. A reviewer should
not have to open the Actions tab to see what a change does.

```yaml
      - name: Post the plan on the pull request
        if: github.event_name == 'pull_request'
        uses: actions/github-script@v7
        env:
          PLAN_OUTCOME: ${{ steps.plan.outcome }}
        with:
          script: |
            const fs = require('fs');
            const path = '${{ env.WORKING_DIR }}/plan.txt';

            let plan = fs.existsSync(path)
              ? fs.readFileSync(path, 'utf8')
              : 'No plan output was produced.';

            const LIMIT = 60000;
            if (plan.length > LIMIT) {
              plan = plan.slice(-LIMIT);
              plan = '...output truncated, see the workflow run for the full plan...\n\n' + plan;
            }

            const ok = process.env.PLAN_OUTCOME === 'success';
            const heading = ok
              ? 'Terraform plan for `environments/dev`'
              : 'Terraform plan FAILED for `environments/dev`';

            const body = [
              '### ' + heading,
              '',
              '<details><summary>Show plan</summary>',
              '',
              '```terraform',
              plan,
              '```',
              '',
              '</details>',
              '',
              '_Workflow: `' + context.workflow + '` &middot; commit `' +
                context.sha.substring(0, 7) + '`_'
            ].join('\n');

            const marker = 'Terraform plan';
            const { data: comments } = await github.rest.issues.listComments({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.issue.number,
            });
            const existing = comments.find(c =>
              c.user.type === 'Bot' && c.body.includes(marker));

            if (existing) {
              await github.rest.issues.updateComment({
                owner: context.repo.owner,
                repo: context.repo.repo,
                comment_id: existing.id,
                body,
              });
            } else {
              await github.rest.issues.createComment({
                owner: context.repo.owner,
                repo: context.repo.repo,
                issue_number: context.issue.number,
                body,
              });
            }

      - name: Fail if the plan failed
        if: steps.plan.outcome == 'failure'
        run: |
          echo "terraform plan failed. See the plan comment on the pull request."
          exit 1
```

Three deliberate choices in there:

- **Read the plan from a file**, not from a step output. Plan text contains
  backticks, quotes, and `${}`, all of which break string interpolation in
  unpleasant ways.
- **Truncate to 60,000 characters.** GitHub rejects comments over 65,536, and a
  large plan will exceed it.
- **Update the existing comment** rather than adding a new one. A pull request
  with nine plan comments is a pull request nobody reads.

### The apply job

```yaml
  terraform-apply:
    name: terraform-apply
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: ${{ env.WORKING_DIR }}

    steps:
      - name: Check out the repository
        uses: actions/checkout@v4

      - name: Sign in to Azure
        uses: azure/login@v2
        with:
          creds: |
            {
              "clientId": "${{ secrets.AZURE_CLIENT_ID }}",
              "clientSecret": "${{ secrets.AZURE_CLIENT_SECRET }}",
              "tenantId": "${{ secrets.AZURE_TENANT_ID }}",
              "subscriptionId": "${{ secrets.AZURE_SUBSCRIPTION_ID }}"
            }

      - name: Install Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Initialize
        run: terraform init -input=false

      - name: Apply
        run: |
          terraform apply -auto-approve -input=false \
            -var-file="${{ env.VAR_FILE }}"

      - name: Show outputs
        run: terraform output
```

`-auto-approve` in a pipeline looks alarming. It is acceptable here only because
of what has to be true before this job can run: the change was proposed in a
pull request, a plan ran and passed, a human read it and approved, and the merge
happened. **The merge is the approval.** In Part 5 you make that a rule rather
than a hope.

Note the apply re-plans rather than using the reviewed `tfplan` file. That file
lives on a runner that no longer exists, and it was built against the PR's
commit rather than the merge commit. Passing a saved plan between jobs is
possible with artifacts and worth doing in production; it is out of scope here.

The complete file is in
[`solutions/lab-10/terraform.yml`](../../solutions/lab-10/terraform.yml) if you
would rather copy it than assemble it.

## Part 4: First run

```powershell
terraform -chdir=environments/dev fmt
terraform -chdir=environments/prod fmt
terraform -chdir=environments/legacy-reporting fmt

git add .github/workflows/terraform.yml
git commit -m "Add GitHub Actions workflow for the dev environment"
git push -u origin feature/lab10-github-actions
```

Open a pull request. Then go to the pull request page in your browser and watch.

Within a few seconds a check appears at the bottom: **terraform-plan**, with a
spinner. About a minute later it turns green, and a comment appears with the
plan folded inside a **Show plan** toggle.

<!-- screenshot: pull request with the terraform-plan check and plan comment -> images/pr-plan-comment.png -->

Open it. That is the same output you have been reading in your terminal all
week, now attached to the proposal, visible to anyone who looks, and permanently
recorded on the pull request.

Since nothing about `environments/dev` actually changed, it should say
**No changes**.

### If the check fails

Click **Details** to see the logs. Work top to bottom; the first red step is the
real problem. See the troubleshooting table at the end.

## Part 5: Make the review a rule

Right now nothing stops you merging without a review. Fix that.

On GitHub: **Settings** > **Branches** > **Add branch ruleset** (or **Add
classic branch protection rule**, depending on what your account shows).

Configure:

- **Branch name pattern / target:** `main`
- **Require a pull request before merging:** on
  - **Required approvals:** 1
- **Require status checks to pass before merging:** on
  - Search for and select **terraform-plan**
- **Require branches to be up to date before merging:** on

Save.

<!-- screenshot: branch protection settings for main -> images/branch-protection.png -->

> **Why your repository is public.** Branch protection and required status
> checks on private repositories need a paid GitHub plan. The organization is on
> the free tier, so the class repositories are public in order to make this
> enforcement real rather than theoretical. Nothing sensitive is in the
> repository: credentials are in Actions secrets and Azure Key Vault.

### Add your reviewer

GitHub will not let you approve your own pull request, which is the point. Add
your neighbor so they can:

**Settings** > **Collaborators** > **Add people** > their GitHub username, with
the **Write** role. They accept the invitation by email or at
[github.com/notifications](https://github.com/notifications).

Do the same for their repository, so you can review theirs.

> Working alone? Ask the instructor to be your reviewer. Failing that, set
> required approvals to 0 and keep the required status check: you lose the
> human gate but keep the automated one, and you should say out loud that this
> is a compromise.

## Part 6: Watch the gate work

Go back to your open pull request and refresh.

The merge button is now grey: **Review required** and **Merging is blocked**.
The plan check is green, but nobody has approved.

<!-- screenshot: blocked merge button showing review required -> images/merge-blocked.png -->

Try clicking it. You cannot. **That is the deliverable of this lab.** Summit's
review policy is no longer a habit somebody might forget; it is a property of
the repository.

1. Send your neighbor the pull request link.
2. They open it, read the plan comment, click **Files changed**, then
   **Review changes** > **Approve** > **Submit review**.
3. Refresh your pull request. The button is green.
4. Review theirs, and actually read their plan before approving. Approving
   without reading is how review theatre starts.

## Part 7: A real change, end to end

Now use the pipeline for what it is for. Do not run Terraform locally at all.

Still on `feature/lab10-github-actions`, make a change a reviewer can evaluate.
In `environments/dev/main.tf`, add a tag to the `locals` block:

```hcl
locals {
  ...
  tags = {
    environment = var.environment
    solution    = var.solution
    owner       = var.owner
    managed_by  = "terraform"
    cost_center = "retail-ops"
  }
}
```

```powershell
terraform -chdir=environments/dev fmt
git add environments/dev/main.tf
git commit -m "Add cost_center tag to the dev environment"
git push
```

Refresh the pull request. The plan check reruns and the comment **updates in
place**:

```
Plan: 0 to add, 7 to change, 0 to destroy.
```

Seven resources getting a new tag, and only the seven that carry tags. A
reviewer can see exactly that, in ten
seconds, without running anything.

1. Neighbor re-approves.
2. Click **Merge pull request**, **Confirm merge**, **Delete branch**.
3. Go to the **Actions** tab immediately.

A **terraform-apply** run has started on `main`. Open it and watch the apply
step scroll. In about a minute:

```
Apply complete! Resources: 0 added, 7 changed, 0 destroyed.
```

<!-- screenshot: Actions tab showing a successful terraform-apply run -> images/apply-run.png -->

Confirm in the portal: every resource in `rg-summit-orders-dev` now carries
`cost_center = retail-ops`.

**You did not run Terraform.** You proposed a change, a machine planned it, a
human approved it, and the merge applied it. Everything is recorded: who
proposed, who approved, what the plan said, when it ran, and what it changed.

```powershell
git switch main
git pull
```

## Part 8: Break it on purpose

One five-minute exercise so the failure mode is familiar.

```powershell
git switch -c fix/deliberate-break
```

In `environments/dev/main.tf`, misspell an argument, for example change
`account_tier` to `account_teir`. Commit and push, open a pull request.

The **terraform-plan** check goes red, and the comment says
**Terraform plan FAILED** with the error inside:

```
Error: Unsupported argument
  on main.tf line 112, in resource "azurerm_storage_account" "orders":
  An argument named "account_teir" is not expected here.
```

The merge is blocked. Nobody had to notice; the pipeline did.

Fix the typo, push again, watch the check go green and the comment update.
Then close the pull request without merging and delete the branch.

## Reflect

1. The service principal has Contributor on the whole subscription. Sketch what
   you would scope it to for a real production pipeline, and how you would
   separate dev from prod credentials.
2. `AZURE_CLIENT_SECRET` is a long-lived password stored in GitHub. What would
   OIDC workload identity federation change about that, and what would stay the
   same?
3. Somebody merges a change that the plan showed as `1 to destroy` and nobody
   noticed. What could you add to the pipeline to make that harder?

## How to verify

- [ ] Opening a pull request against `environments/dev` posts a plan comment
- [ ] `main` cannot be merged into without an approval and a passing `terraform-plan` check
- [ ] Merging triggers `terraform-apply`, and it succeeds
- [ ] The `cost_center` tag is on every dev resource, applied by the pipeline
- [ ] A broken configuration produces a red check and a readable error in the comment
- [ ] No credential appears in any workflow log

## If you get stuck

| Symptom | Cause and fix |
|---|---|
| `Error building ARM Config: obtain subscription from Azure CLI` | The `ARM_*` env block is missing or a secret name is misspelled. Names are case sensitive. |
| `AADSTS7000215: Invalid client secret provided` | The secret is wrong, truncated, or has trailing whitespace. Rerun the SP script to generate a new one and update `AZURE_CLIENT_SECRET`. |
| `AuthorizationFailed` on the state storage account | The SP lacks Contributor on the subscription. Rerun the SP script. |
| `does not have secrets get permission` | The SP is missing Key Vault Secrets User. Rerun the SP script, which grants it, and allow a minute to propagate. |
| `terraform fmt -check` fails | Run `terraform fmt -recursive` locally, commit the result. |
| `No value for required variable "allowed_ssh_source"` | The `TF_VAR_ALLOWED_SSH_SOURCE` secret is missing, or the env line is misspelled. The env var name is case sensitive and lowercase after `TF_VAR_`. |
| The plan comment never appears | Check `permissions: pull-requests: write` at the top of the workflow. |
| The workflow does not run at all | The `paths:` filter did not match your change, or the file is not at `.github/workflows/terraform.yml` exactly. |
| `Error acquiring the state lock` | Two runs at once. Confirm the `concurrency:` block is present. If a lock is stuck, get the ID from the log and `terraform force-unlock <ID>` locally. |
| Branch protection options are missing | The repository is private. Make it public: Settings > General > Danger Zone > Change visibility. |
| You cannot approve your own pull request | Correct, and intentional. Add a collaborator. |
| The apply job never runs after merge | Its `if:` requires `push` to `refs/heads/main`. Check you merged rather than closing, and that `paths:` matched. |

## Challenge (optional)

Add a second workflow, `terraform-prod.yml`, for `environments/prod`. It is this
file with three changes: the `paths` filter, `WORKING_DIR`, and `VAR_FILE`.

Then think about what production should have that dev does not: a longer
required review, a GitHub Environment with required reviewers on the apply job,
a separate service principal, or `apply` gated on a manual dispatch rather than
the merge. Write your answer in the pull request description.

## Cleanup

Keep everything. Deallocate both VMs if you are stopping for the day.

Leave the service principal in place; Lab 11 and Lab 12 use the pipeline.

## Congratulations!

Summit's Orders platform is now delivered the way it should be. Changes arrive
as proposals, a machine checks them, a human approves them, and the merge is the
deployment. Nobody needs standing rights to change infrastructure, and every
change has a record of who, what, when, and why.

Lab 11 is about what happens on all the days after this one.
