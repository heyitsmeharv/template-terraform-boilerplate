#!/usr/bin/env bash
set -euo pipefail

# plan.sh
# - Creates a plan for a chosen deployable root under infra/env/<aws-account>.
# - Uses env.tfvars to supply values.
# - Outputs a tfplan file so apply uses an exact, reviewed plan.
#
# Usage:
#   infra/scripts/plan.sh <aws-account>

ENVIRONMENT="${1:-}"
if [ -z "$ENVIRONMENT" ]; then
  echo "Usage: infra/scripts/plan.sh <aws-account>"
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_DIR="$ROOT_DIR/env/$ENVIRONMENT"

if [ ! -d "$ENV_DIR" ]; then
  echo "Environment folder not found: $ENV_DIR"
  echo "Usage: infra/scripts/plan.sh <aws-account>"
  exit 1
fi

echo "Plan"
echo "Target: $ENVIRONMENT"
echo ""

cd "$ENV_DIR"

if [ ! -f "backend.hcl" ]; then
  echo "backend.hcl not found in: $ENV_DIR"
  echo "Fix (local): run bootstrap for this environment:"
  echo "  bash $ROOT_DIR/scripts/bootstrap-state.sh $ENVIRONMENT --region ${AWS_REGION:-eu-west-2}"
  echo "Fix (CI): generate backend.hcl before running plan.sh"
  exit 1
fi

terraform init -input=false -backend-config=backend.hcl

terraform plan -input=false \
  -var-file="env.tfvars" \
  -out="tfplan"

echo "plan complete for environment: $ENVIRONMENT"
echo "Plan saved to: $ENV_DIR/tfplan"
