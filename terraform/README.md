# Terraform — Infrastructure as Code for the React S3 + CloudFront Demo

This folder contains the **Terraform code that manages the AWS infrastructure** for the React demo app:

- S3 bucket (private, blocks all public access)
- CloudFront distribution (global CDN, free HTTPS via the default `*.cloudfront.net` cert)
- CloudFront Origin Access Control (OAC) — the modern, AWS-recommended way for CloudFront to read from a private S3 bucket
- S3 bucket policy granting only this CloudFront distribution read access
- IAM user used by GitHub Actions to deploy, with a least-privilege inline policy

Everything you previously did by clicking around the AWS Console is now declared in `.tf` files. You can reproduce, modify, or tear down the infrastructure with a single command.

> **Live site:** https://d3e4ns0lp7i9a5.cloudfront.net

---

## Table of Contents

1. [What this manages](#1-what-this-manages)
2. [Why Terraform (and what problem it solves)](#2-why-terraform-and-what-problem-it-solves)
3. [Decisions and justifications](#3-decisions-and-justifications)
4. [File layout](#4-file-layout)
5. [Prerequisites](#5-prerequisites)
6. [First-time setup (fresh AWS account)](#6-first-time-setup-fresh-aws-account)
7. [Adopting existing AWS resources (terraform import)](#7-adopting-existing-aws-resources-terraform-import)
8. [Day-to-day usage](#8-day-to-day-usage)
9. [Common gotchas](#9-common-gotchas)
10. [Cleanup](#10-cleanup)
11. [What is NOT managed by Terraform](#11-what-is-not-managed-by-terraform)

---

## 1. What this manages

| AWS Resource | Terraform resource | Purpose |
|---|---|---|
| S3 bucket | `aws_s3_bucket.website` | Stores built React files |
| Public access block | `aws_s3_bucket_public_access_block.website` | Locks bucket — no public reads |
| Bucket policy | `aws_s3_bucket_policy.website` | Allows only our CloudFront distribution to read |
| CloudFront OAC | `aws_cloudfront_origin_access_control.website` | Secure CloudFront-to-S3 handshake |
| CloudFront distribution | `aws_cloudfront_distribution.website` | Global CDN + HTTPS |
| IAM user | `aws_iam_user.github_actions` | Deploy robot for GitHub Actions |
| IAM policy (inline) | `aws_iam_user_policy.github_actions_deploy` | Least-privilege deploy permissions |

---

## 2. Why Terraform (and what problem it solves)

When the infrastructure was set up manually via the AWS Console, there were real problems:

- **Not repeatable.** Spinning up a copy for a teammate or another region meant clicking through dozens of screens again.
- **Not reviewable.** No PR for "I changed the CloudFront cache policy."
- **Hard to clean up.** At the end of a project, you have to remember every resource you created.
- **Error-prone.** Easy to miss a checkbox or fat-finger a name.

Terraform turns infrastructure into **code**. The state of AWS is now declared in `.tf` files, version-controlled in git, reviewable via pull requests, and reproducible with `terraform apply`.

---

## 3. Decisions and justifications

These are the design decisions I made for this project, with the reasoning behind each.

### 3.1 Scope: AWS resources only, not GitHub Secrets or the workflow file

**Decision:** Terraform manages S3, CloudFront, and IAM. It does NOT manage GitHub Secrets or the GitHub Actions workflow file.

**Reasoning:** GitHub Secrets and workflows are GitHub concerns, not AWS. Mixing them into Terraform would require a `github` provider, GitHub PAT tokens, and an extra trust boundary — for no real benefit at this scale. Keeping IaC focused on AWS is the cleaner separation of concerns.

**Trade-off considered:** A more advanced setup could manage GitHub Secrets via Terraform (using the `integrations/github` provider). That's worth doing in larger teams where secrets rotation is automated, but it's overkill for a single-engineer demo.

### 3.2 State management: local `.tfstate` (with a note about remote state for production)

**Decision:** Terraform state is stored locally in `terraform.tfstate`, not in remote state.

**Reasoning:** Remote state (S3 + DynamoDB for state locking) is the production pattern because it allows multiple engineers to collaborate without overwriting each other's state. But it introduces a chicken-and-egg problem: you need an S3 bucket and DynamoDB table to STORE state, and those would themselves be Terraform resources. For a single-engineer demo, local state is simpler and equally safe — as long as `.tfstate` is gitignored (which it is).

**What changes for production:**

```hcl
# Add this block to versions.tf
terraform {
  backend "s3" {
    bucket         = "terraform-state-bucket"
    key            = "react-s3-cloudfront-demo/terraform.tfstate"
    region         = "eu-north-1"
    dynamodb_table = "terraform-state-locks"
    encrypt        = true
  }
}
```

### 3.3 Repo layout: same repo under `terraform/` subfolder

**Decision:** Terraform code lives in `terraform/` inside the same repo as the React app and CI/CD workflow.

**Reasoning:** One repo = one mental model for the tester. App code, infra code, and CI/CD config in one place. A separate repo would split context across multiple `git clone` operations with no real benefit at this scale.

### 3.4 Migration: `terraform import`, not destroy + recreate

**Decision:** I used `terraform import` to adopt the existing manually-created AWS resources into Terraform's state, rather than deleting them and recreating fresh ones.

**Reasoning:** Import preserves the existing CloudFront distribution and its public URL (`d3e4ns0lp7i9a5.cloudfront.net`). Destroying and recreating would have generated a NEW URL, breaking any links shared elsewhere. Import is also the more realistic case — in real jobs you frequently inherit existing infrastructure that you need to bring under management.

**Trade-off considered:** Import is more upfront work than `apply` from scratch — one import command per resource (7 total). But the trade-off (a few minutes of import work vs. broken URLs) was clearly worth it.

### 3.5 CloudFront price class: `PriceClass_100` (North America + Europe only)

**Decision:** Use `PriceClass_100` instead of `PriceClass_All`.

**Reasoning:** Cheaper, sufficient for a demo. Most viewers are in NA/EU. Easy to switch to `PriceClass_All` (every edge location worldwide) by changing one line if needed.

### 3.6 IAM policy scope: specific ARNs only, not wildcards

**Decision:** The GitHub Actions IAM policy specifies the exact bucket ARN and CloudFront distribution ARN as resources — not `Resource: "*"`.

**Reasoning:** Principle of least privilege. If the GitHub Actions access key ever leaked, the blast radius is limited to this specific S3 bucket and this specific CloudFront distribution. An attacker can't touch any other AWS resources.

### 3.7 Variables and `.tfvars` split

**Decision:** Variable shapes are declared in `variables.tf` (committed), real values are in `terraform.tfvars` (gitignored). A `terraform.tfvars.example` template is committed.

**Reasoning:** Standard 12-factor pattern — code is shared, config is per-environment/user. A new engineer clones the repo, copies `terraform.tfvars.example` to `terraform.tfvars`, fills in their values, runs `terraform apply`. Clean separation, no risk of someone accidentally committing real values.

---

## 4. File layout
terraform/
├── versions.tf                  # Terraform & AWS provider version pinning
├── variables.tf                 # Input variable declarations (committed)
├── outputs.tf                   # Outputs printed after apply (committed)
├── main.tf                      # All AWS resource definitions
├── terraform.tfvars.example     # Template for terraform.tfvars (committed)
├── terraform.tfvars             # Actual values (gitignored)
├── .gitignore                   # Excludes state, .tfvars, .terraform/
└── README.md                    # This file
After `terraform init` and `terraform apply` you will also have:
terraform/
├── .terraform/                  # Downloaded provider plugins (gitignored)
├── .terraform.lock.hcl          # Locks plugin versions (committed)
├── terraform.tfstate            # Current state (gitignored)
└── terraform.tfstate.backup     # Previous state (gitignored)
---

## 5. Prerequisites

| Tool | Version | Install |
|---|---|---|
| Terraform | 1.5+ | `brew tap hashicorp/tap && brew install hashicorp/tap/terraform` |
| AWS CLI v2 | latest | `brew install awscli` |
| AWS credentials | configured | Run `aws sts get-caller-identity` to verify |

Verify all three:

```bash
terraform --version       # should print v1.5+
aws --version             # should print aws-cli/2.x
aws sts get-caller-identity   # should print your account ID
```

---

## 6. First-time setup (fresh AWS account)

If you're spinning this up in an AWS account that does NOT already have the resources, follow this flow.

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars and set s3_bucket_name to something globally unique
terraform init
terraform plan
terraform apply
```

When `apply` finishes, Terraform prints the CloudFront URL. The site won't load until you upload built files to S3 — usually done by the GitHub Actions workflow on the first push to `main`.

---

## 7. Adopting existing AWS resources (terraform import)

If the AWS resources were created manually first (as they were in this project), use `terraform import` to bring them under Terraform's management WITHOUT recreating them.

You need the actual AWS IDs of each resource:

```bash
# S3 bucket
terraform import aws_s3_bucket.website <BUCKET-NAME>
terraform import aws_s3_bucket_public_access_block.website <BUCKET-NAME>
terraform import aws_s3_bucket_policy.website <BUCKET-NAME>

# CloudFront
terraform import aws_cloudfront_origin_access_control.website <OAC-ID>
terraform import aws_cloudfront_distribution.website <DISTRIBUTION-ID>

# IAM
terraform import aws_iam_user.github_actions <IAM-USER-NAME>
terraform import aws_iam_user_policy.github_actions_deploy <IAM-USER-NAME>:GitHubActionsDeployPolicy
```

Find the IDs:

```bash
# CloudFront distributions
aws cloudfront list-distributions --query "DistributionList.Items[*].[Id,DomainName]" --output table

# CloudFront OACs
aws cloudfront list-origin-access-controls --query "OriginAccessControlList.Items[*].[Id,Name]" --output table

# S3 buckets
aws s3 ls

# IAM users
aws iam list-users --query "Users[*].UserName" --output table
```

After importing, run `terraform plan`. Some cosmetic differences are expected (tags, descriptions, name conventions). Decide per diff whether to:

- Run `terraform apply` to push the code's settings into AWS, OR
- Edit `.tf` files to match the current AWS state exactly

In this project I chose to apply — the diffs were improvements (modernized policy version, consistent tags, stricter ARN matching).

---

## 8. Day-to-day usage

Three commands cover ~95% of what you'll do:

| Command | What it does | When to use |
|---|---|---|
| `terraform plan` | Preview changes without applying. Read-only. | ALWAYS run this before apply. Treat it like `git diff`. |
| `terraform apply` | Make the changes. Prompts for `yes` confirmation. | After you've reviewed the plan and are confident. |
| `terraform output` | Print all output values (URL, bucket, etc.) | When you need values for other tools (GitHub Secrets, scripts). |

Useful variations:

```bash
terraform output -raw cloudfront_url     # just the URL, scriptable
terraform output -json                   # all outputs as JSON
terraform fmt                            # auto-format all .tf files
terraform validate                       # check syntax without hitting AWS
```

---

## 9. Common gotchas

### "Terraform asks for `s3_bucket_name`" interactively

You're missing `terraform.tfvars` in the working directory. Copy from the template:

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars and fill in your bucket name
```

### Plan says "X to destroy" — STOP

Never apply a destructive plan without understanding why. Look at which resources are being destroyed:

- If it's because you renamed a resource in code → check Terraform docs for `moved` blocks (renames without destroying)
- If it's something else → revert your changes and ask for help

### `Error: BucketAlreadyOwnedByYou`

You're trying to create a bucket that already exists. Either:

- Use `terraform import` to adopt the existing bucket, OR
- Change `s3_bucket_name` in `terraform.tfvars` to something else

### CloudFront changes take a long time to apply

CloudFront propagation can take 2-5 minutes. Terraform waits for it. Be patient.

### `Error: ResourceNotFoundException` after running an import

You typed the wrong AWS ID. Run the `aws ... list ...` commands in section 7 to confirm the correct ID.

---

## 10. Cleanup

To delete every AWS resource Terraform created:

```bash
terraform destroy
```

You'll see a plan listing everything that will be destroyed, then a prompt for `yes`. This will fully remove:

- The S3 bucket (must be empty first — empty via `aws s3 rm s3://<bucket> --recursive` if it has files)
- The CloudFront distribution (the destroy command disables it first, then deletes — adds ~10 minutes to the operation)
- The IAM user and policy
- Everything else

After `destroy`, the public URL stops working immediately.

> If you only want to destroy ONE resource: `terraform destroy -target=aws_s3_bucket.website`. Avoid `-target` in normal use — it can leave state and reality out of sync.

---

## 11. What is NOT managed by Terraform

Deliberately out of scope (managed elsewhere):

- **GitHub Actions workflow** — `.github/workflows/deploy.yml` in the parent repo
- **GitHub Repository Secrets** — set manually in GitHub Settings → Secrets and variables → Actions
- **The IAM user's access keys** — created/rotated manually in AWS Console, then pasted into GitHub Secrets. Terraform can manage access keys (`aws_iam_access_key` resource), but storing the resulting secret in state file is awkward — usually handled outside IaC.
- **The React app source code** — lives in the parent repo

This separation is intentional. Each tool owns one thing.

---

## Credits

Built by **Danish Khan** ([@dkhanbhirsh](https://github.com/dkhanbhirsh))

