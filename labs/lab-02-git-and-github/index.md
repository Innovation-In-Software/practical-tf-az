# Lab 2: Git and Pull Requests in VS Code

## Overview

In Lab 1 you saw infrastructure described as a file. A file is only useful to a
team if there is somewhere safe to keep it, a way to propose a change to it, and
a record of who changed what. That is Git and GitHub, and from here on **every
change you make this week travels through them**.

This lab has two halves:

- **Part 1 to 4:** the everyday loop, run for real against Summit's shared
  `az-tf-ops` repository. Clone, branch, edit, commit, push, open a pull
  request, and review a teammate's.
- **Part 5:** create your **own** copy of the Orders repository. Labs 3 through
  12 all build in that copy, so you get to run pipelines and set branch rules on
  a repository you control.

Almost all of this happens with buttons in VS Code. The equivalent commands are
shown alongside, because you will meet them in scripts and in error messages.

> If you have never opened a pull request before, this is the most important
> hour of the course. The Terraform is learnable in a day. Working as a team
> through reviewed changes is the part that actually changes how Summit
> operates.

## Objectives

By the end of this lab you can:

- Clone a repository from GitHub inside VS Code
- Create a branch, stage changes, and commit them from the Source Control panel
- Push a branch and open a pull request with the GitHub Pull Requests extension
- Review someone else's pull request, leave a comment, and approve it
- Explain why nobody commits straight to `main`

## What you'll need

- The [setup guide](../setup/index.md) completed, including GitHub sign-in
  inside VS Code
- Write access to `Innovation-In-Software/az-tf-ops` (your instructor arranged
  this)
- A neighbor to swap pull requests with. If you are working alone, the
  instructor will play the neighbor.

## Part 1: Clone the shared repository

Cloning makes a full local copy of the repository, including its entire history.

1. In VS Code, press `Ctrl+Shift+P` to open the Command Palette.
2. Type `Git: Clone` and press Enter.
3. Choose **Clone from GitHub**, then start typing `Innovation-In-Software/az-tf-ops`
   and select it.
4. When asked where to put it, choose `C:\Users\Administrator\Downloads\terraform\labs`.
5. When VS Code asks **Would you like to open the cloned repository?**, click
   **Open**.

<!-- screenshot: VS Code Command Palette showing Git: Clone -> images/clone-palette.png -->

The command line equivalent, for reference:

```powershell
cd C:\Users\Administrator\Downloads\terraform\labs
git clone https://github.com/Innovation-In-Software/az-tf-ops.git
cd az-tf-ops
```

Look at the bottom left corner of the VS Code window. It shows the current
branch, which right now is `main`.

### Look around

Open the Explorer panel. The repository has:

```
az-tf-ops/
  README.md
  .gitignore
  docs/
    naming-and-tagging.md
  students/
    README.md
```

Nothing here is Terraform yet. That is deliberate: this lab is about the
workflow, not the tool.

## Part 2: Branch before you change anything

`main` is the branch everyone shares. It is supposed to reflect what is actually
deployed. You never edit it directly. Instead you make a branch: a private line
of work that starts as an exact copy of `main`.

1. Click the branch name (`main`) in the bottom left status bar.
2. Choose **Create new branch...**.
3. Name it `feature/<your-github-username>-intro`, for example
   `feature/jrivera-intro`.
4. Press Enter.

<!-- screenshot: VS Code branch picker with Create new branch highlighted -> images/create-branch.png -->

The status bar now shows your branch name. Command line equivalent:

```powershell
git switch -c feature/jrivera-intro
```

> **Why the naming?** Putting your username in the branch name means twenty
> people can work in the same repository without colliding. `feature/` is
> Summit's prefix for new work; `fix/` is the prefix for corrections.

## Part 3: Make a change and commit it

1. In the Explorer, open the `students/` folder.
2. Create a new file named `<your-github-username>.md`, for example
   `jrivera.md`.
3. Put a few lines in it:

   ```markdown
   # Jamie Rivera

   - Team: Summit Retail cloud operations
   - Azure region I work in: eastus
   - Something I want to stop doing by hand: rebuilding staging
   ```

4. Save the file (`Ctrl+S`).

Now look at the **Source Control** panel (the branching icon in the activity
bar, third one down). It shows a badge with `1`, and your new file listed under
**Changes** with a green `U` next to it, for untracked.

### Stage the change

Staging is you saying "this specific change belongs in the next commit."

5. Hover over your file in the Source Control panel and click the **+**
   (Stage Changes). The file moves up into **Staged Changes**.

<!-- screenshot: VS Code Source Control panel with a staged file -> images/stage-change.png -->

### Commit it

6. In the message box at the top of the Source Control panel, write a real
   commit message:

   ```
   Add Jamie Rivera to the students directory
   ```

7. Click the **Commit** button (the checkmark).

Command line equivalent:

```powershell
git add students/jrivera.md
git commit -m "Add Jamie Rivera to the students directory"
```

A good commit message says what the change does, in the present tense, in one
line. "Update file" and "asdf" are how a history becomes useless.

> Your commit is still only on your machine. Nobody else can see it. That is the
> next step.

## Part 4: Push and open a pull request

### Push your branch

1. In the Source Control panel, click **Publish Branch** (or the sync icon if it
   says that instead).
2. If VS Code asks for permission to use your GitHub account, allow it.

Command line equivalent:

```powershell
git push -u origin feature/jrivera-intro
```

Your branch now exists on GitHub. Still nothing has changed on `main`.

### Open the pull request

A **pull request (PR)** is a request to merge your branch into `main`, plus a
place to discuss it before that happens.

1. Click the **GitHub** icon in the activity bar (the cat outline).
2. Under **Pull Requests**, click **Create Pull Request**. VS Code should
   pre-select your branch.
3. Check the two ends of the request carefully:
   - **Base:** `Innovation-In-Software/az-tf-ops` `main`
   - **Merge:** your branch
4. Give it a title: `Add Jamie Rivera to the students directory`
5. In the description, say what changed and why. One or two sentences is plenty:

   ```
   Adds my entry to students/ as part of Lab 2.
   No infrastructure change.
   ```

6. Click **Create**.

<!-- screenshot: GitHub Pull Requests extension, Create Pull Request form -> images/create-pr.png -->

VS Code opens the pull request view. Notice what it gives you: the description,
the list of commits, the files changed, and a place for reviewers to comment.

7. Open the same pull request in your browser at
   [github.com/Innovation-In-Software/az-tf-ops/pulls](https://github.com/Innovation-In-Software/az-tf-ops/pulls)
   so you can see what a reviewer sees.

## Part 5: Review a teammate's pull request

This is the half of the workflow people skip, and it is the half that catches
mistakes.

1. Pair up with a neighbor and swap pull request links. (No neighbor? The
   instructor has a pull request waiting for you.)
2. In VS Code, under the **GitHub** icon, expand **All Open** and click your
   neighbor's pull request.
3. Click **Files Changed** (or the **Description** view's file list) to see the
   diff. Added lines are green, removed lines are red.
4. Hover over a specific line in the diff and click the **+** that appears.
   Leave a comment. Make it a real one, for example:

   ```
   Nice. Could you add which subscription you're using, so we can find your
   resources if something is left running?
   ```

5. Click **Start Review**, then **Submit Review**, and choose **Approve**.

<!-- screenshot: reviewing a PR in VS Code with a line comment -> images/review-pr.png -->

6. Go back to your own pull request. Read the comment your neighbor left. If it
   asks for a change, make it: edit the file locally, stage, commit, and push
   again. The pull request updates automatically. You do not open a new one.

> **The point:** a change to Summit's infrastructure will go through exactly
> this. Somebody proposes it, somebody else reads it, and only then does it
> reach `main`. In Lab 10 you make that a rule the repository enforces rather
> than a habit people remember.

7. Once approved, merge your pull request from the GitHub web page: click
   **Merge pull request**, then **Confirm merge**, then **Delete branch**.

8. Back in VS Code, switch to `main` and pull the merged change:

   - Click the branch name in the status bar, choose `main`
   - Click the sync icon in the status bar

   Command line equivalent:

   ```powershell
   git switch main
   git pull
   ```

   Your neighbor's entry and your own are both there now. That is the loop:
   **pull, branch, commit, push, pull request, merge, pull.**

## Part 6: Create your own copy of the Orders repository

The shared repository was the right place to practice, because it is shared.
For the rest of the week you need a repository you fully control: you will store
credentials in it, run pipelines from it, and set the rules on its `main`
branch. Twenty people cannot do that to one repository.

1. Go to
   [github.com/Innovation-In-Software/az-tf-ops](https://github.com/Innovation-In-Software/az-tf-ops)
   in your browser.
2. Click the green **Use this template** button, then **Create a new
   repository**.
3. Fill in:
   - **Owner:** your own GitHub account (not the organization)
   - **Repository name:** `az-tf-ops-<your-github-username>`, for example
     `az-tf-ops-jrivera`
   - **Visibility:** **Public**
4. Click **Create repository**.

<!-- screenshot: GitHub Use this template dialog -> images/use-template.png -->

> **Why public?** Branch protection rules and required status checks, which you
> set up in Lab 10, are only available on public repositories under the
> organization's GitHub plan. There is nothing sensitive in this repository:
> real credentials live in GitHub Actions secrets and in Azure Key Vault, never
> in the files.

Now clone your copy next to the shared one:

1. `Ctrl+Shift+P`, `Git: Clone`, **Clone from GitHub**
2. Pick `<your-username>/az-tf-ops-<your-username>`
3. Save it into `C:\Users\Administrator\Downloads\terraform\labs`
4. **Open** it when prompted

```powershell
cd C:\Users\Administrator\Downloads\terraform\labs
git clone https://github.com/<your-username>/az-tf-ops-<your-username>.git
```

You now have two folders under `C:\Users\Administrator\Downloads\terraform\labs`:

| Folder | Used for |
|---|---|
| `az-tf-ops` | Lab 2 only, the shared practice repository |
| `az-tf-ops-<your-username>` | **Labs 3 to 12.** This is "your repo" from now on |

Close the shared repository window in VS Code so you do not confuse the two.

## How to verify

You are done when all of these are true:

- [ ] Your pull request into `Innovation-In-Software/az-tf-ops` was approved and merged
- [ ] You left a review comment on a teammate's pull request
- [ ] `git log --oneline -3` on `main` shows your commit in the history
- [ ] `C:\Users\Administrator\Downloads\terraform\labs\az-tf-ops-<your-username>` exists, is open in VS Code, and its
      GitHub page shows **Public**

## If you get stuck

| Symptom | Fix |
|---|---|
| `Permission denied` or `403` on push | You are pushing to the shared repo but were not added to the students team. Ask the instructor. |
| VS Code will not sign in to GitHub | Sign out from the Accounts icon and sign in again. If a browser tab hangs, try a different browser. |
| Your PR shows dozens of unrelated file changes | You branched from an old `main`. Run `git switch main`, `git pull`, then create your branch again. |
| "Create Pull Request" is greyed out | You have not pushed your branch yet. Click **Publish Branch** first. |
| The PR base repository is wrong | On the create form, click the base dropdown and set it explicitly. Getting this wrong sends your change to the wrong repository. |

## Cleanup

Nothing to clean up in Azure. Leave both repositories in place.

## Congratulations!

You ran the loop that every remaining lab depends on: branch, commit, push,
propose, review, merge. You also have your own copy of Summit's Orders
repository, which is where you write your first real Terraform in Lab 3.

From here, when a lab says "commit your work," it means this loop. It will feel
slow twice and then it will feel normal.
