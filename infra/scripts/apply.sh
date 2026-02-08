#!/usr/bin/env bash
set -euo pipefail

# apply.sh
# - Applies a previously generated plan file (tfplan).
# - Avoids "surprise applies" and matches a safer CI pattern.
#
# Usage:
#   infra/scripts/apply.sh <aws-account>

ENVIRONMENT="${1:-}"
if [ -z "$ENVIRONMENT" ]; then
  echo "Usage: infra/scripts/apply.sh <aws-account>"
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_DIR="$ROOT_DIR/env/$ENVIRONMENT"

if [ ! -d "$ENV_DIR" ]; then
  echo "Environment folder not found: $ENV_DIR"
  echo "Usage: infra/scripts/apply.sh <aws-account>"
  exit 1
fi

echo "Apply"
echo "Target: $ENVIRONMENT"
echo ""

cd "$ENV_DIR"

if [ ! -f "backend.hcl" ]; then
  echo "backend.hcl not found in: $ENV_DIR"
  echo "Fix (local): run bootstrap for this environment."
  exit 1
fi

terraform init -input=false -backend-config=backend.hcl

if [ ! -f "tfplan" ]; then
  echo "No tfplan found in $ENV_DIR"
  echo "Run: infra/scripts/plan.sh $ENVIRONMENT"
  exit 1
fi

terraform apply -input=false "tfplan"
echo "apply complete for environment: $ENVIRONMENT"
