# Terraform Greenfield — React S3 + CloudFront with Remote State

This folder contains a **greenfield** Terraform setup: all AWS resources are created fresh by `terraform apply`, with no manual setup or `terraform import` steps. State is stored remotely in S3 with locking via S3's built-in conditional writes.

This is the "do it the right way from the start" approach. It runs **alongside** the original `terraform/` folder — both can be used independently.

> **Live site (this setup):** https://d20xvlw1ii7zja.cloudfront.net

---

## Why this exists (and how it differs from `../terraform/`)

The original `../terraform/` setup was built incrementally:
1. Resources created manually via AWS Console
2. Terraform code written after the fact
3. `terraform import` used to bring existing resources under management
4. State stored locally in `terraform.tfstate`

That works, but has two real problems for a new project:
- **`import` is a one-time workaround**, not a normal pattern. Starting greenfield, you wouldn't ever need it.
- **Local state is fragile.** If the laptop dies or the state file is deleted, Terraform forgets what it created. AWS resources are stuck orphaned with nothing tracking them.

This folder fixes both:
- All resources created from scratch via `terraform apply`. No `import`, no Console clicking.
- State stored in S3 with versioning, encryption, and locking. Survives laptop loss, supports team collaboration.

---

## Table of contents

1. [Architecture](#1-architecture)
2. [Decisions and justifications](#2-decisions-and-justifications)
3. [The bootstrap problem (and how we solved it)](#3-the-bootstrap-problem-and-how-we-solved-it)
4. [Prerequisites](#4-prerequisites)
5. [First-time bootstrap (one-time, manual)](#5-first-time-bootstrap-one-time-manual)
6. [Setup and apply](#6-setup-and-apply)
7. [Day-to-day usage](#7-day-to-day-usage)
8. [State locking — why and how it works here](#8-state-locking--why-and-how-it-works-here)
9. [Cleanup](#9-cleanup)
10. [Comparison with the original `terraform/` folder](#10-comparison-with-the-original-terraform-folder)

---

## 1. Architecture

Same AWS architecture as the original setup, just managed under a different Terraform configuration:

| AWS Resource | Terraform resource | Purpose |
|---|---|---|
| S3 bucket | `aws_s3_bucket.website` | Stores built React files |
| Public access block | `aws_s3_bucket_public_access_block.website` | Bucket is private; no direct public reads |
| Bucket policy | `aws_s3_bucket_policy.website` | Allows ONLY our CloudFront distribution |
| CloudFront OAC | `aws_cloudfront_origin_access_control.website` | Secure handshake between CloudFront and S3 |
| CloudFront distribution | `aws_cloudfront_distribution.website` | Global CDN + free HTTPS |
| IAM user | `aws_iam_user.github_actions` | Deploy robot (currently no CI/CD wired to this setup -- see section 6) |
| IAM inline policy | `aws_iam_user_policy.github_actions_deploy` | Least-privilege deploy permissions |

Names differ from the original (`-greenfield` suffix) so both setups can coexist.

---

## 2. Decisions and justifications

### 2.1 Greenfield (not `terraform import`)

**Decision:** Create everything fresh via `terraform apply`, no `import`.

**Reasoning:** `import` is a workaround for adopting infra that was created outside Terraform. For a NEW project, there's nothing to import -- you just declare what you want and apply. Using import in a greenfield setup would be code smell, signalling either confusion or unnecessary complexity.

**Trade-off:** Greenfield creates a NEW CloudFront URL (different from the original setup's URL). For a brand-new project, that's not a downside -- you don't have any existing links to break.

### 2.2 Remote state in S3

**Decision:** State file stored in S3 bucket `danish-terraform-state`, not on the laptop.

**Reasoning:**
- **Survives laptop loss.** Local state means if the laptop dies, Terraform forgets what it manages. The resources still exist in AWS, but you can no longer update or destroy them through Terraform. You'd have to re-import each one manually.
- **Team-shareable.** Any teammate can `terraform apply` from any machine and see the same state. Local state is single-machine-only.
- **Versioned.** The state bucket has S3 versioning enabled. If a Terraform run somehow corrupts the state file, we can roll back to the previous version.
- **Encrypted at rest.** State files can contain sensitive metadata (resource ARNs, account IDs). The bucket has default AES256 encryption.

This was specific feedback from review on the original setup: *"avoid local state... shouldn't have situations where you have to end up saying it was there yesterday."*

### 2.3 Locking with S3 `use_lockfile` (not DynamoDB)

**Decision:** Use S3's built-in conditional writes for state locking (`use_lockfile = true`) instead of a separate DynamoDB table.

**Reasoning:** Until Terraform 1.10, the standard locking mechanism was a DynamoDB table with a specific schema. Terraform 1.10+ supports a simpler approach where the lock is just a small JSON file in the state bucket itself, protected by S3's conditional write semantics.

Both achieve the same goal (prevent two engineers from running `terraform apply` at the same time). The newer approach has:
- One fewer AWS resource to provision and manage
- No separate billing surface for locking
- Simpler mental model (state and lock live in the same place)

Older tutorials still show DynamoDB. Both work; this setup uses the modern pattern.

**Note on leftover bootstrap:** A DynamoDB table `danish-terraform-locks` was initially provisioned before the deprecation warning surfaced. It is currently unused. Left in place for now (PAY_PER_REQUEST means zero cost when idle), but can be cleaned up via:

```bash
aws dynamodb delete-table --table-name danish-terraform-locks --region eu-north-1
```

### 2.4 Bootstrap is manual (chicken-and-egg)

**Decision:** The state bucket `danish-terraform-state` was created manually via AWS CLI, NOT by Terraform.

**Reasoning:** To use Terraform to manage the state bucket, you would need a state file to store the result. But the state file lives in the very bucket you're trying to create. Classic chicken-and-egg.

Three real-world solutions exist:
1. **Manual bootstrap** (what this uses) -- create state infra once via CLI, then Terraform manages everything else.
2. **Separate "bootstrap" Terraform** with its own LOCAL state, only used to create the remote-state infra. Adds complexity.
3. **Use a hosted service** like Terraform Cloud. Adds cost and a new dependency.

For this project, the manual bootstrap is the simplest defensible choice. The exact commands are documented in section 5 so the setup is reproducible.

### 2.5 Coexistence with the original setup

**Decision:** This folder lives alongside the original `terraform/` folder, both committed to the same repo. Both manage independent AWS infrastructure.

**Reasoning:** Review feedback was explicit: *"you will have one more setup."* This is the second setup. The first one is preserved so the original URL keeps working and the two approaches can be compared side-by-side.

---

## 3. The bootstrap problem (and how we solved it)

To use remote state, you need:
- An S3 bucket to STORE the state file
- (Historically) A DynamoDB table to LOCK the state during writes

But Terraform can't create its own state storage -- there's no state to track the creation. So one of those must be set up outside Terraform.

**What we did:**

The state bucket `danish-terraform-state` was created once via AWS CLI with versioning, encryption, and public access block enabled. The exact commands are in section 5.

**What we did NOT do:**

We did NOT use a separate Terraform "bootstrap" module. That pattern exists but adds another folder, another `apply`, and another piece of local state -- diminishing returns for a single-engineer setup.

---

## 4. Prerequisites

| Tool | Version | Install |
|---|---|---|
| Terraform | 1.10+ | `brew tap hashicorp/tap && brew install hashicorp/tap/terraform` |
| AWS CLI v2 | latest | `brew install awscli` |
| AWS credentials | configured | `aws sts get-caller-identity` should return your account ID |

The 1.10+ requirement is because of `use_lockfile`. On older Terraform, fall back to the deprecated `dynamodb_table` parameter.

---

## 5. First-time bootstrap (one-time, manual)

If you are setting this up in a fresh AWS account, run these commands ONCE before doing anything else with Terraform. They create the S3 bucket where Terraform will store its state.

```bash
# 1. Create the state bucket
aws s3api create-bucket \
  --bucket YOUR-TERRAFORM-STATE-BUCKET-NAME \
  --region eu-north-1 \
  --create-bucket-configuration LocationConstraint=eu-north-1

# 2. Enable versioning -- lets us recover if state ever gets corrupted
aws s3api put-bucket-versioning \
  --bucket YOUR-TERRAFORM-STATE-BUCKET-NAME \
  --versioning-configuration Status=Enabled

# 3. Enable encryption at rest
aws s3api put-bucket-encryption \
  --bucket YOUR-TERRAFORM-STATE-BUCKET-NAME \
  --server-side-encryption-configuration '{
    "Rules": [
      {
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        }
      }
    ]
  }'

# 4. Block all public access. State files are never public.
aws s3api put-public-access-block \
  --bucket YOUR-TERRAFORM-STATE-BUCKET-NAME \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

After this one-time setup, you'll need to update `versions.tf` in this folder to point at your bucket name (the `backend "s3" { bucket = ... }` field).

---

## 6. Setup and apply

After the bootstrap is done:

```bash
cd terraform-greenfield

# 1. Copy the template, then edit terraform.tfvars with your bucket name
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set s3_bucket_name to something globally unique

# 2. Initialize Terraform -- connects to remote state
terraform init

# 3. Preview what will be created
terraform plan
# Expected: "Plan: 7 to add, 0 to change, 0 to destroy"

# 4. Apply
terraform apply
# Type 'yes' when prompted. Takes ~3-5 minutes (CloudFront propagation).
```

After apply finishes, the outputs print:
- `cloudfront_url` -- the new live URL
- `s3_bucket_name` -- the website bucket
- `iam_user_name` -- the deploy user

To upload the React app to the new bucket:

```bash
cd ..
npm run build
aws s3 sync dist/ s3://YOUR-WEBSITE-BUCKET-NAME/ --delete
aws cloudfront create-invalidation --distribution-id YOUR-DISTRIBUTION-ID --paths "/*"
```

**Note on CI/CD:** GitHub Actions currently deploys to the original `../terraform/` setup only. The greenfield setup is updated manually via the `aws s3 sync` and `aws cloudfront create-invalidation` commands above. Wiring CI/CD here would require:

1. Creating access keys for the new IAM user `github-actions-react-s3-cloudfront-greenfield`
2. Adding those keys to GitHub Secrets (alongside or replacing the existing ones)
3. Updating the workflow to deploy to both buckets, or switching to the new one

Left as a follow-up because the goal of this task was to demonstrate IaC, not to migrate CI/CD.

---

## 7. Day-to-day usage

| Command | What it does |
|---|---|
| `terraform plan` | Preview changes. Always run before apply. |
| `terraform apply` | Apply changes. Asks for `yes` confirmation. |
| `terraform output` | Print all outputs (URL, IDs). |
| `terraform output -raw cloudfront_url` | Just the URL -- useful in scripts. |
| `terraform fmt` | Auto-format all `.tf` files. |
| `terraform validate` | Check syntax without hitting AWS. |

---

## 8. State locking — why and how it works here

When you run `terraform apply`, Terraform first writes a small lock file to the state bucket (something like `terraform.tfstate.tflock`). If another `apply` is in flight from anyone else, the second one is blocked until the first completes and removes the lock.

Without locking, two concurrent `apply` operations could:
- Both read the same starting state
- Each make different changes
- Both write back their version -> one overwrites the other -> state and reality diverge

S3 conditional writes (`If-None-Match`) guarantee that only one process can write the lock file at a time. The same primitive used here is what guarantees uniqueness of file uploads in many distributed systems.

You'll see `Acquiring state lock` and `Releasing state lock` lines in the Terraform output around every plan/apply.

---

## 9. Cleanup

To delete all AWS resources managed by this folder:

```bash
terraform destroy
```

Note: this does NOT delete the state bucket itself (`danish-terraform-state`) since that was bootstrapped manually. To fully clean up, you'd also delete the bucket via CLI:

```bash
# Make sure the bucket is empty first (versioned buckets need extra care)
aws s3 rm s3://danish-terraform-state --recursive
aws s3api delete-bucket --bucket danish-terraform-state --region eu-north-1

# And if you want to remove the orphaned DynamoDB lock table:
aws dynamodb delete-table --table-name danish-terraform-locks --region eu-north-1
```

---

## 10. Comparison with the original `terraform/` folder

| Aspect | `../terraform/` | `terraform-greenfield/` (this folder) |
|---|---|---|
| Resource creation | Manual (Console) -> imported | `terraform apply` from scratch |
| `terraform import` used? | Yes (7 resources) | No |
| State storage | Local (`terraform.tfstate`) | Remote (S3) |
| State locking | None | S3 `use_lockfile` |
| CloudFront URL | `d3e4ns0lp7i9a5.cloudfront.net` (preserved from manual setup) | `d20xvlw1ii7zja.cloudfront.net` (fresh) |
| Resource names | `react-s3-cloudfront-demo-*` | `react-s3-cloudfront-demo-greenfield-*` |
| CI/CD wired up | Yes (GitHub Actions) | No (manual upload, see section 6) |
| Recommended for | Reference / learning import workflow | New projects from day 1 |

Both setups demonstrate the same end result. The original shows how to adopt existing infrastructure; this one shows how to do it cleanly from scratch.

---

## Credits

Built by **Danish Khan** ([@dkhanbhirsh](https://github.com/dkhanbhirsh))

