#!/usr/bin/env bash

# destroy.sh
# - Destroys everything under infra/env/<environment>.
# - Deliberately interactive: Terraform prints the full list of resources it is
#   about to delete and waits for you to type "yes". Do not add -auto-approve.
# - Prints the AWS account and caller ARN first, because Terraform's own
#   confirmation shows resource addresses only, and those look near-identical
#   across environments.
#
# Usage:
#   bash infra/scripts/destroy.sh <environment>

set -euo pipefail

ENVIRONMENT="${1:-}"
if [ -z "$ENVIRONMENT" ]; then
  echo "Usage: bash infra/scripts/destroy.sh <environment>"
  exit 1
fi
shift

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_DIR="$ROOT_DIR/env/$ENVIRONMENT"

if [ ! -d "$ENV_DIR" ]; then
  echo "Environment folder not found: $ENV_DIR"
  exit 1
fi

cd "$ENV_DIR"

if [ ! -f "backend.hcl" ]; then
  echo "No backend.hcl found in $ENV_DIR"
  echo "Run: bash infra/scripts/write-backend-hcl.sh $ENVIRONMENT"
  exit 1
fi

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text 2>/dev/null || true)"
CALLER_ARN="$(aws sts get-caller-identity --query Arn --output text 2>/dev/null || true)"

if [ -z "$ACCOUNT_ID" ] || [ "$ACCOUNT_ID" = "None" ] || [ -z "$CALLER_ARN" ] || [ "$CALLER_ARN" = "None" ]; then
  echo "Could not determine AWS account/principal. Are you authenticated?"
  echo "Tip: set AWS_PROFILE and run: aws sts get-caller-identity"
  exit 1
fi

echo "Destroy"
echo "Environment: $ENVIRONMENT"
echo "Account:     $ACCOUNT_ID"
echo "Caller ARN:  $CALLER_ARN"
echo ""
echo "This is irreversible."
echo "Make sure you have captured anything you still need before continuing."
echo ""

terraform init -input=false -backend-config=backend.hcl

terraform destroy -var-file="env.tfvars"

# Any tfplan left over from plan.sh is now meaningless.
rm -f "tfplan"

echo "destroy complete for environment: $ENVIRONMENT"
