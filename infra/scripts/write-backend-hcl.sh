#!/usr/bin/env bash
set -euo pipefail

# write-backend-hcl.sh
# - Writes an env-bound write-backend.hcl at:
#   infra/env/<environment>/write-backend.hcl
# - Uses the current AWS identity to derive the account ID.
# - Matches the same naming convention used by bootstrap-state.sh.
#
# Usage:
#   bash infra/scripts/write-backend-hcl.sh <environment> [--region eu-west-2] [--project-name template-terraform-boilerplate]
#
# Notes:
# - write-backend.hcl is intentionally NOT committed to git.

usage() {
  echo "Usage: bash infra/scripts/write-backend-hcl.sh <environment> [--region eu-west-2] [--project-name template-terraform-boilerplate]"
  exit 1
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENVIRONMENT="${1:-}"
shift || true
if [ -z "$ENVIRONMENT" ]; then
  usage
fi

REGION="${AWS_REGION:-eu-west-2}"
PROJECT_NAME="template-terraform-boilerplate"

while [ "${1:-}" != "" ]; do
  case "$1" in
    --region)
      shift
      REGION="${1:-}"
      ;;
    --project-name)
      shift
      PROJECT_NAME="${1:-}"
      ;;
    *)
      echo "Unknown arg: $1"
      usage
      ;;
  esac
  shift || true
done

ENV_DIR="$ROOT_DIR/env/$ENVIRONMENT"
if [ ! -d "$ENV_DIR" ]; then
  echo "Environment folder not found: $ENV_DIR"
  echo "Create it under infra/env/ and try again."
  exit 1
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "AWS CLI is required."
  exit 1
fi

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text 2>/dev/null || true)"
CALLER_ARN="$(aws sts get-caller-identity --query Arn --output text 2>/dev/null || true)"

if [ -z "$ACCOUNT_ID" ] || [ "$ACCOUNT_ID" = "None" ]; then
  echo "Could not determine AWS account ID. Are you authenticated?"
  exit 1
fi

STATE_BUCKET="${PROJECT_NAME}-${ACCOUNT_ID}-${REGION}-tfstate"
LOCK_TABLE="${PROJECT_NAME}-${ACCOUNT_ID}-${REGION}-tflocks"
STATE_KEY="${PROJECT_NAME}/${ENVIRONMENT}/terraform.tfstate"

cat > "$ENV_DIR/backend.hcl" <<EOF
bucket         = "$STATE_BUCKET"
key            = "$STATE_KEY"
region         = "$REGION"
dynamodb_table = "$LOCK_TABLE"
encrypt        = true
EOF

echo "Wrote $ENV_DIR/backend.hcl"
echo "Account:    $ACCOUNT_ID"
echo "Caller ARN: ${CALLER_ARN:-<unknown>}"
