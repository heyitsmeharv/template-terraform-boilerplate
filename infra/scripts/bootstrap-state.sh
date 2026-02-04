#!/usr/bin/env bash
set -euo pipefail

# bootstrap-state.sh
# - Creates Terraform remote state prerequisites in the CURRENT AWS account:
#   - S3 bucket for state (versioning + encryption + public access block)
#   - DynamoDB table for state locking
#   - Terraform execution role (assumable by you locally + GitHub Actions via OIDC)
# - Also sets up GitHub Actions OIDC:
#   - IAM OIDC provider for token.actions.githubusercontent.com (idempotent)
#   - GitHub OIDC role that Actions assumes
# - Generates infra/backend.hcl used by terraform init
#
# Usage (Git Bash, from repo root):
#   bash infra/scripts/bootstrap-state.sh sandbox --region eu-west-2
#
# Notes
#   - This script creates resources in whichever AWS account your current auth points to.
#   - Always check the printed Account + Caller ARN before continuing.
#   - If you want a different account, switch AWS_PROFILE first, then rerun.

usage() {
  echo "Usage: bash infra/scripts/bootstrap-state.sh <environment> [--region eu-west-2] [--role-name TerraformExecutionRole] [--github-role-name GitHubOIDCTerraformRole] [--github-repo owner/repo]"
  echo ""
  echo "Args:"
  echo "  <environment>       Environment folder name under infra/env/ (e.g., sandbox)"
  echo ""
  echo "Options:"
  echo "  --region            AWS region (default: AWS_REGION or eu-west-2)"
  echo "  --role-name         Terraform execution role name (default: TerraformExecutionRole)"
  echo "  --github-role-name  GitHub OIDC role name (default: GitHubOIDCTerraformRole)"
  echo "  --github-repo       GitHub repo in owner/repo format (auto-detected if possible)"
  exit 1
}

if [ ! -d "infra" ]; then
  echo "Run this from the repo root (infra/ folder not found)."
  exit 1
fi

ENVIRONMENT="${1:-}"
shift || true
if [ -z "$ENVIRONMENT" ]; then
  usage
fi

REGION="${AWS_REGION:-eu-west-2}"
ROLE_NAME="TerraformExecutionRole"
GITHUB_ROLE_NAME="GitHubOIDCTerraformRole"
GITHUB_REPO=""

while [ "${1:-}" != "" ]; do
  case "$1" in
    --region)
      shift
      REGION="${1:-}"
      ;;
    --role-name)
      shift
      ROLE_NAME="${1:-}"
      ;;
    --github-role-name)
      shift
      GITHUB_ROLE_NAME="${1:-}"
      ;;
    --github-repo)
      shift
      GITHUB_REPO="${1:-}"
      ;;
    *)
      echo "Unknown arg: $1"
      usage
      ;;
  esac
  shift || true
done

# Prereqs
if ! command -v aws >/dev/null 2>&1; then
  echo "AWS CLI is required."
  echo "Run: bash infra/scripts/prereqs.sh"
  exit 1
fi

PROJECT_NAME="template-terraform-boilerplate"

# Confirm identity early (avoid creating resources in the wrong account)
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text 2>/dev/null || true)"
CALLER_ARN="$(aws sts get-caller-identity --query Arn --output text 2>/dev/null || true)"

if [ -z "$ACCOUNT_ID" ] || [ "$ACCOUNT_ID" = "None" ] || [ -z "$CALLER_ARN" ] || [ "$CALLER_ARN" = "None" ]; then
  echo "Could not determine AWS account/principal. Are you authenticated?"
  echo "Tip: set AWS_PROFILE and run: aws sts get-caller-identity"
  exit 1
fi

# Try to detect owner/repo from git remote if not provided
if [ -z "$GITHUB_REPO" ] && command -v git >/dev/null 2>&1; then
  ORIGIN_URL="$(git config --get remote.origin.url 2>/dev/null || true)"

  # Supports:
  # - https://github.com/owner/repo.git
  # - git@github.com:owner/repo.git
  if echo "$ORIGIN_URL" | grep -q "github.com"; then
    GITHUB_REPO="$(echo "$ORIGIN_URL" \
      | sed -E 's#^git@github\.com:##' \
      | sed -E 's#^https://github\.com/##' \
      | sed -E 's#\.git$##')"
  fi
fi

if [ -z "$GITHUB_REPO" ]; then
  echo ""
  echo "Could not auto-detect the GitHub repo."
  echo "Fix: re-run with --github-repo owner/repo"
  echo "Example:"
  echo "  bash infra/scripts/bootstrap-state.sh $ENVIRONMENT --region $REGION --github-repo heyitsmeharv/template-terraform-boilerplate"
  echo ""
  exit 1
fi

STATE_BUCKET="${PROJECT_NAME}-${ACCOUNT_ID}-${REGION}-tfstate"
LOCK_TABLE="${PROJECT_NAME}-${ACCOUNT_ID}-${REGION}-tflocks"

ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
GITHUB_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${GITHUB_ROLE_NAME}"

echo ""
echo "Bootstrap (remote state + roles)"
echo "Environment:   $ENVIRONMENT"
echo "Account:       $ACCOUNT_ID"
echo "Region:        $REGION"
echo "Caller ARN:    $CALLER_ARN"
echo "GitHub repo:   $GITHUB_REPO"
echo "State bucket:  $STATE_BUCKET"
echo "Lock table:    $LOCK_TABLE"
echo "TF role:       $ROLE_NAME"
echo "GitHub role:   $GITHUB_ROLE_NAME"
echo ""

###############################################################################
# 1) Create S3 bucket
###############################################################################
echo "→ Ensuring S3 bucket exists..."
if aws s3api head-bucket --bucket "$STATE_BUCKET" >/dev/null 2>&1; then
  echo "  - Bucket exists: $STATE_BUCKET"
else
  if [ "$REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$STATE_BUCKET" >/dev/null
  else
    aws s3api create-bucket \
      --bucket "$STATE_BUCKET" \
      --create-bucket-configuration "LocationConstraint=$REGION" >/dev/null
  fi
  echo "  - Bucket created: $STATE_BUCKET"
fi

echo "→ Configuring bucket (versioning, encryption, public access block)..."
aws s3api put-bucket-versioning \
  --bucket "$STATE_BUCKET" \
  --versioning-configuration Status=Enabled >/dev/null

aws s3api put-bucket-encryption \
  --bucket "$STATE_BUCKET" \
  --server-side-encryption-configuration '{
    "Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]
  }' >/dev/null

aws s3api put-public-access-block \
  --bucket "$STATE_BUCKET" \
  --public-access-block-configuration '{
    "BlockPublicAcls":true,
    "IgnorePublicAcls":true,
    "BlockPublicPolicy":true,
    "RestrictPublicBuckets":true
  }' >/dev/null

echo "  - Bucket configured"

###############################################################################
# 2) Create DynamoDB lock table
###############################################################################
echo ""
echo "→ Ensuring DynamoDB lock table exists..."
if aws dynamodb describe-table --table-name "$LOCK_TABLE" >/dev/null 2>&1; then
  echo "  - Table exists: $LOCK_TABLE"
else
  aws dynamodb create-table \
    --table-name "$LOCK_TABLE" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST >/dev/null

  echo "  - Table created: $LOCK_TABLE"
  echo "  - Waiting for table to become ACTIVE..."
  aws dynamodb wait table-exists --table-name "$LOCK_TABLE"
fi

###############################################################################
# 3) Create Terraform execution role
###############################################################################
echo ""
echo "→ Ensuring Terraform execution role exists..."

if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  echo "  - Role exists: $ROLE_NAME"
else
  echo "  - Creating role: $ROLE_NAME"

  # Start with local caller trusted; we’ll update later to also trust the GitHub role.
  TRUST_POLICY="$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowAssumeFromLocalCaller",
      "Effect": "Allow",
      "Principal": { "AWS": "${CALLER_ARN}" },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
)"

  aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document "$TRUST_POLICY" >/dev/null

  echo "  - Role created: $ROLE_NAME"
fi

# Permissions for TerraformExecutionRole
# NOTE: For templates, starting broad is common so your first applies don’t get blocked.
# Tighten later when you know exactly what resources you manage.
aws iam attach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess" >/dev/null || true

###############################################################################
# 4) GitHub Actions OIDC provider + role
###############################################################################
echo ""
echo "→ Ensuring GitHub OIDC provider exists..."

OIDC_URL="https://token.actions.githubusercontent.com"
OIDC_PROVIDER_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"

if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_PROVIDER_ARN" >/dev/null 2>&1; then
  echo "  - OIDC provider exists"
else
  # GitHub OIDC uses a stable root CA chain. This thumbprint is the commonly used value for token.actions.githubusercontent.com.
  # If AWS ever requires an update, you can recreate the provider with the new thumbprint.
  THUMBPRINT="6938fd4d98bab03faadb97b34396831e3780aea1"

  aws iam create-open-id-connect-provider \
    --url "$OIDC_URL" \
    --client-id-list "sts.amazonaws.com" \
    --thumbprint-list "$THUMBPRINT" >/dev/null

  echo "  - OIDC provider created"
fi

echo "→ Ensuring GitHub OIDC role exists..."

if aws iam get-role --role-name "$GITHUB_ROLE_NAME" >/dev/null 2>&1; then
  echo "  - Role exists: $GITHUB_ROLE_NAME"
else
  echo "  - Creating role: $GITHUB_ROLE_NAME"

  # Restrict to this repo (owner/repo). You can tighten further to a branch if you want.
  GITHUB_TRUST_POLICY="$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowGitHubActionsOIDC",
      "Effect": "Allow",
      "Principal": {
        "Federated": "${OIDC_PROVIDER_ARN}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:${GITHUB_REPO}:*"
        }
      }
    }
  ]
}
EOF
)"

  aws iam create-role \
    --role-name "$GITHUB_ROLE_NAME" \
    --assume-role-policy-document "$GITHUB_TRUST_POLICY" >/dev/null

  echo "  - Role created: $GITHUB_ROLE_NAME"
fi

# Permissions for GitHubOIDCTerraformRole
# Same story: start broad for templates; tighten later.
aws iam attach-role-policy \
  --role-name "$GITHUB_ROLE_NAME" \
  --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess" >/dev/null || true

###############################################################################
# 5) Update TerraformExecutionRole trust to include GitHub role
###############################################################################
echo ""
echo "→ Updating TerraformExecutionRole trust (local + GitHub)..."

UPDATED_TF_TRUST_POLICY="$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowAssumeFromLocalCaller",
      "Effect": "Allow",
      "Principal": { "AWS": "${CALLER_ARN}" },
      "Action": "sts:AssumeRole"
    },
    {
      "Sid": "AllowAssumeFromGitHubOIDCRole",
      "Effect": "Allow",
      "Principal": { "AWS": "${GITHUB_ROLE_ARN}" },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
)"

aws iam update-assume-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-document "$UPDATED_TF_TRUST_POLICY" >/dev/null

echo "  - Trust updated"

###############################################################################
# 6) Write infra/backend.hcl
###############################################################################
echo ""
echo "→ Writing infra/backend.hcl..."

STATE_KEY="${PROJECT_NAME}/${ENVIRONMENT}/terraform.tfstate"

mkdir -p infra

cat > infra/backend.hcl <<EOF
bucket         = "$STATE_BUCKET"
key            = "$STATE_KEY"
region         = "$REGION"
dynamodb_table = "$LOCK_TABLE"
encrypt        = true
role_arn       = "$ROLE_ARN"
EOF

echo "  - Wrote infra/backend.hcl"
echo ""
echo "    Bootstrap complete"
echo ""
echo "Next (local):"
echo "  source infra/scripts/use-env.sh $ENVIRONMENT"
echo "  bash infra/scripts/whoami.sh"
echo "  cd infra/env/$ENVIRONMENT"
echo "  terraform init -backend-config=../../backend.hcl"
echo ""
echo "Next (GitHub):"
echo "  Create GitHub Environment named: $ENVIRONMENT"
echo "  Add Environment secret AWS_ROLE_ARN = $GITHUB_ROLE_ARN"
echo ""
