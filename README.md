# React + AWS S3 + CloudFront Demo

A minimal React app deployed to AWS as a static website using **S3** for storage and **CloudFront** as a global CDN, with **GitHub Actions** auto-deploying on every push to `main`.

**Live demo:** https://d3e4ns0lp7i9a5.cloudfront.net

The page displays a build timestamp that updates with every deploy. Push a code change → watch the timestamp change on the live site within ~30-60 seconds. That's visible proof CI/CD works end-to-end.

---

## Table of Contents

1. [What this is and why](#1-what-this-is-and-why)
2. [Architecture](#2-architecture)
3. [Prerequisites](#3-prerequisites)
4. [Project structure](#4-project-structure)
5. [Local development](#5-local-development)
6. [AWS setup (from scratch)](#6-aws-setup-from-scratch)
7. [GitHub setup](#7-github-setup)
8. [The deploy workflow explained](#8-the-deploy-workflow-explained)
9. [Verifying CI/CD works](#9-verifying-cicd-works)
10. [Troubleshooting](#10-troubleshooting)
11. [Cost estimate](#11-cost-estimate)
12. [Cleanup (delete everything)](#12-cleanup-delete-everything)

---

## 1. What this is and why

This project answers a common question: *"How do I host a React app on AWS so that users worldwide get it fast, over HTTPS, with automatic deploys when I push code?"*

The answer is the standard static-site pattern:

- **S3** stores the built static files (HTML, CSS, JS).
- **CloudFront** is AWS's CDN. It caches your files at edge locations in 400+ cities and serves them with HTTPS.
- **GitHub Actions** automates the build + upload + cache invalidation on every push to `main`.

It's the same pattern Netflix, Airbnb, and most modern SPAs use for their marketing sites and dashboards.

---

## 2. Architecture
Developer
               │
               │  git push main
               ▼
        ┌─────────────────┐
        │     GitHub      │
        │   (repository)  │
        └────────┬────────┘
                 │ triggers
                 ▼
        ┌─────────────────┐
        │ GitHub Actions  │
        │   (CI runner)   │
        │                 │
        │  1. npm ci      │
        │  2. npm build   │
        │  3. aws s3 sync │
        │  4. invalidate  │
        └────────┬────────┘
                 │ uploads
                 ▼
        ┌─────────────────┐
        │   AWS S3        │
        │ (private bucket)│
        └────────┬────────┘
                 │ origin
                 ▼
        ┌─────────────────┐
        │ AWS CloudFront  │
        │ (global CDN +   │
        │  HTTPS)         │
        └────────┬────────┘
                 │ serves
                 ▼
              Users
          (worldwide)
**Key security note:** the S3 bucket is **private** — users cannot reach it directly. CloudFront uses an **Origin Access Control (OAC)** mechanism to read from S3 on behalf of users. This way the bucket isn't publicly exposed.

---

## 3. Prerequisites

Install or have these ready before starting:

| Tool | Version | Check command |
|---|---|---|
| Node.js | 20+ | `node --version` |
| npm | 10+ | `npm --version` |
| git | any recent | `git --version` |
| AWS account | free tier OK | sign up at https://aws.amazon.com |
| GitHub account | free | sign up at https://github.com |

You will also need:
- **Access to AWS Console** in your browser (https://console.aws.amazon.com)
- **A GitHub Personal Access Token** with `repo` scope if you plan to push from the command line (https://github.com/settings/tokens)

---

## 4. Project structure
react-s3-cloudfront-demo/
├── .github/
│   └── workflows/
│       └── deploy.yml          ← CI/CD pipeline definition
├── public/                     ← static assets served as-is
├── src/
│   ├── App.jsx                 ← main React component (the visible page)
│   ├── App.css                 ← styles
│   ├── main.jsx                ← React entry point
│   └── index.css               ← global styles
├── index.html                  ← HTML entry point
├── vite.config.js              ← Vite config (injects BUILD_TIME)
├── package.json
└── README.md
---

## 5. Local development

Clone the repo and run locally:

```bash
git clone https://github.com/dkhanbhirsh/react-s3-cloudfront-demo.git
cd react-s3-cloudfront-demo
npm install
npm run dev
```

Open http://localhost:5173 in your browser. You'll see the demo page with the build timestamp.

To produce the production build that gets deployed:

```bash
npm run build
```

This outputs static files to `dist/`. To preview the production build locally:

```bash
npm run preview
```

Open http://localhost:4173.

---

## 6. AWS setup (from scratch)

You only need to do this **once** per project. If you're replicating this setup for yourself, follow these steps carefully.

### 6.1 Create the S3 bucket

1. Log in to [AWS Console](https://console.aws.amazon.com).
2. Top-right region selector → choose your region (this guide uses **`eu-north-1` / Europe (Stockholm)**).
3. Search bar → **S3** → click the service.
4. Click **Create bucket**.
5. Fill in:
   - **Bucket name:** must be globally unique. Example: `your-name-react-s3-cloudfront-demo`
   - **Region:** same as Step 2
   - **Object Ownership:** ACLs disabled (default)
   - **Block Public Access:** keep ALL 4 checkboxes checked. The bucket stays private — CloudFront will access it via OAC.
   - **Versioning, Tags, Encryption:** leave defaults
6. Click **Create bucket**.

> 📝 Write down your bucket name. You'll need it in step 6.3 and 7.

### 6.2 Build and upload your React app manually (one-time test)

This isn't strictly required because GitHub Actions will do it later, but it's a useful sanity check that the bucket works.

```bash
npm run build
```

Then in AWS Console:

1. Open your bucket → click **Upload**.
2. Click **Add files** → select `index.html`, `favicon.svg`, and any other root files in `dist/`.
3. Click **Add folder** → select the `assets/` folder.
4. Scroll down → click **Upload**.
5. After upload, confirm the bucket has all 5 items.

### 6.3 Create the CloudFront distribution

1. AWS Console search → **CloudFront** → **Create distribution**.
2. **Distribution name:** `react-s3-cloudfront-demo`
3. **Distribution type:** Single website or app
4. **Route 53 managed domain:** leave empty (we use the default CloudFront URL)
5. Click **Next**.
6. **Origin type:** Amazon S3
7. **S3 origin:** click **Browse S3** → choose your bucket from step 6.1
8. **Origin path:** leave empty
9. **Allow private S3 bucket access to CloudFront:** ✅ **check this** — this auto-creates the bucket policy for OAC
10. **Origin settings:** Use recommended
11. **Cache settings:** Use recommended cache settings tailored to serving S3 content
12. Click **Next**.
13. **Web Application Firewall (WAF):** **Do not enable security protections** (WAF costs ~$14/month — not needed for a demo)
14. Click **Next**.
15. Review and click **Create distribution**.

After creation:

- Note the **Distribution domain name** (looks like `d1234abc.cloudfront.net`). This is your public URL.
- Note the **Distribution ID** (looks like `EZTJ2US3WG8X0`). You'll need this for the IAM policy and GitHub Secrets.
- CloudFront automatically sets `index.html` as the **Default root object**. Verify this on the General tab.

> ⏳ CloudFront takes 5-10 minutes to deploy globally. Status will show "Deploying" until done.

After deploy, visit `https://YOUR-DISTRIBUTION-DOMAIN.cloudfront.net` — your manually-uploaded app should appear.

### 6.4 Create the IAM user for GitHub Actions

GitHub Actions needs AWS credentials. We'll create a dedicated user with only the permissions needed (principle of least privilege).

1. AWS Console search → **IAM** → **Users** → **Create user**.
2. **User name:** `github-actions-react-s3-cloudfront`
3. **Provide user access to the AWS Management Console:** leave **unchecked** (this user is for programmatic use only)
4. Click **Next**.
5. **Permissions options:** **Attach policies directly**.
6. Don't attach any of the predefined policies. Just click **Next**.
7. Review and click **Create user**.

#### Add a custom inline policy

1. Click on the newly created user → **Permissions** tab.
2. **Add permissions** dropdown → **Create inline policy**.
3. Switch to the **JSON** tab.
4. Replace the contents with the following — **replace `YOUR-BUCKET-NAME` and `YOUR-DISTRIBUTION-ID` and `YOUR-AWS-ACCOUNT-ID` with your values**:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowS3DeployUploads",
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:GetObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::YOUR-BUCKET-NAME",
                "arn:aws:s3:::YOUR-BUCKET-NAME/*"
            ]
        },
        {
            "Sid": "AllowCloudFrontInvalidation",
            "Effect": "Allow",
            "Action": [
                "cloudfront:CreateInvalidation"
            ],
            "Resource": "arn:aws:cloudfront::YOUR-AWS-ACCOUNT-ID:distribution/YOUR-DISTRIBUTION-ID"
        }
    ]
}
```

5. Click **Next** → name the policy `GitHubActionsDeployPolicy` → **Create policy**.

#### Generate access keys

1. On the user page → **Security credentials** tab.
2. Scroll to **Access keys** → **Create access key**.
3. Select **Application running outside AWS** → Next.
4. Description tag: `GitHub Actions deploy`.
5. Click **Create access key**.
6. **🚨 Copy both values NOW** using the copy icon (📋) next to each. The Secret access key is shown only once.

> ⚠️ **CRITICAL:** When copying the access key and secret, use the **copy icon** (📋), NOT mouse highlight + Cmd+C. Mouse selection sometimes grabs trailing whitespace, which causes "signature does not match" errors when GitHub Actions tries to authenticate.

Save both keys to a local password manager or temporary file. **Never commit them to git.**

---

## 7. GitHub setup

### 7.1 Create the repo

1. https://github.com/new
2. Repository name: `react-s3-cloudfront-demo`
3. Public visibility
4. Don't initialize with README/license
5. Create repository

### 7.2 Push the code

From your local project:

```bash
git init
git add .
git commit -m "Initial commit"
git branch -M main
git remote add origin https://github.com/YOUR-USERNAME/react-s3-cloudfront-demo.git
git push -u origin main
```

### 7.3 Add Repository Secrets

Go to: **Settings → Secrets and variables → Actions → New repository secret**.

Add these 5 secrets:

| Name | Value |
|---|---|
| `AWS_ACCESS_KEY_ID` | Access key from step 6.4 (starts with `AKIA`) |
| `AWS_SECRET_ACCESS_KEY` | Secret access key from step 6.4 (40 characters) |
| `AWS_REGION` | Your region, e.g. `eu-north-1` |
| `S3_BUCKET_NAME` | Your bucket name from step 6.1 |
| `CLOUDFRONT_DISTRIBUTION_ID` | Distribution ID from step 6.3, e.g. `EZTJ2US3WG8X0` |

These are encrypted at rest and never visible in logs or code, even on a public repo.

---

## 8. The deploy workflow explained

The CI/CD pipeline is defined in `.github/workflows/deploy.yml`. Walking through it:

```yaml
on:
  push:
    branches: [ main ]
  workflow_dispatch:
```

Triggers: every push to `main`, plus a manual "Run workflow" button.

```yaml
runs-on: ubuntu-latest
```

GitHub provides a fresh Ubuntu VM for each run. Free for public repos.

The steps in order:

1. **Checkout** — pulls the latest code from the branch
2. **Setup Node.js** — installs Node 20 and caches npm dependencies
3. **Install dependencies** — `npm ci` (reproducible install from `package-lock.json`)
4. **Build** — `npm run build` produces `dist/`. The build timestamp gets baked in at this step.
5. **Configure AWS credentials** — uses GitHub Secrets to authenticate as the IAM user
6. **Sync dist/ to S3** — `aws s3 sync` uploads new/changed files and deletes obsolete ones. Long-cached except for `index.html`.
7. **Upload index.html separately** — `index.html` is uploaded with `Cache-Control: no-cache` so users always fetch the latest entry point. Assets (with hashed filenames) stay cached for a year.
8. **Invalidate CloudFront cache** — tells CloudFront edge servers to re-fetch from S3 on the next request

Total runtime: roughly 30-40 seconds.

---

## 9. Verifying CI/CD works

Once everything is set up:

1. Make a small visible change in `src/App.jsx` (change an emoji, edit a heading, etc.)
2. Commit and push:
```bash
   git add src/App.jsx
   git commit -m "Verify CI/CD"
   git push origin main
```
3. Open https://github.com/YOUR-USERNAME/react-s3-cloudfront-demo/actions and watch the new run go green ✅.
4. Hard-refresh the live URL (`Cmd+Shift+R` on Mac, `Ctrl+Shift+R` on Windows/Linux).
5. The page should show:
   - Your visible change
   - A newer **build timestamp** matching the deploy time

If the timestamp updated, the entire pipeline worked.

---

## 10. Troubleshooting

### "The request signature we calculated does not match the signature you provided"

This is the most common GitHub Actions failure on first setup.

**Cause:** The `AWS_SECRET_ACCESS_KEY` GitHub Secret has a typo, trailing whitespace, or got copied incorrectly with mouse selection.

**Fix:**
1. Go to IAM → your user → Security credentials → delete the existing access key
2. Create a new access key
3. On the credentials page, use the **copy icon (📋)** next to each value (NOT mouse + Cmd+C)
4. In GitHub Secrets, delete and re-add both `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`
5. Trigger a redeploy: `git commit --allow-empty -m "Retry" && git push`

### Page loads but shows "Access Denied" or blank

**Cause:** CloudFront's Default root object isn't set to `index.html`.

**Fix:**
1. CloudFront Console → your distribution → General tab → Settings → Edit
2. Set **Default root object:** `index.html` → Save

### Code change pushed but live site still shows old version

**Possible causes:**

- **Workflow hasn't finished:** check the Actions tab.
- **CloudFront cache hasn't propagated:** wait 1-3 minutes.
- **Browser cache:** hard-refresh (`Cmd+Shift+R`) or open in incognito.

### Workflow fails at "Sync dist to S3" with "AccessDenied"

**Cause:** IAM policy doesn't allow access to the bucket name in your GitHub secret.

**Fix:** Double-check `S3_BUCKET_NAME` secret matches the actual bucket name, and the IAM inline policy's `Resource` ARN matches.

### "Could not find a valid Docker environment" (irrelevant for this project)

Different project. Skip.

---

## 11. Cost estimate

For a small demo with light traffic, expect to pay **basically $0/month** thanks to the AWS Free Tier:

| Service | Free tier (first 12 months) | This demo's usage |
|---|---|---|
| S3 storage | 5 GB | ~200 KB |
| S3 requests | 20,000 GET, 2,000 PUT/month | well under |
| CloudFront data transfer out | 1 TB/month (always free, not just 12 months) | well under |
| CloudFront HTTPS requests | 10 million/month (always free) | well under |
| CloudFront invalidations | 1,000 free paths/month | 1 per deploy = fine |
| IAM users / policies | always free | 1 user |

**After the 12-month free tier expires:** S3 costs about $0.023/GB/month for storage. Even storing 1 GB and serving moderate traffic costs <$1/month.

You only need to worry about cost if your site serves millions of users.

---

## 12. Cleanup (delete everything)

If you want to remove this demo from AWS (e.g., to avoid even minor charges after free tier ends):

1. **CloudFront:** select your distribution → Disable → wait for Disabled status → Delete
2. **S3:** open the bucket → Empty the bucket → Delete the bucket
3. **IAM:** open the user → delete the access key, then delete the user

GitHub repo and code can be deleted via GitHub UI.

---

## Credits

Built by **Danish Khan** ([@dkhanbhirsh](https://github.com/dkhanbhirsh))

