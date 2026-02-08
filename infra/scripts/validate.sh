#!/usr/bin/env bash
set -euo pipefail

# validate.sh
# - Local/CI quality gate for a deployable root under infra/env/<aws-account>
# - Includes:
#   1) terraform fmt (writes changes)
#   2) terraform validate (syntax + internal consistency)
#   3) tflint (provider-aware linting)
#
# Usage:
#   infra/scripts/validate.sh <aws-account>
#
# Install tflint:
#   https://github.com/terraform-linters/tflint

ENVIRONMENT="${1:-}"
if [ -z "$ENVIRONMENT" ]; then
  echo "Usage: infra/scripts/validate.sh <aws-account>"
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_DIR="$ROOT_DIR/env/$ENVIRONMENT"

if [ ! -d "$ENV_DIR" ]; then
  echo "Environment folder not found: $ENV_DIR"
  echo "Usage: infra/scripts/validate.sh <aws-account>"
  exit 1
fi

echo "Validate (fmt → terraform validate → tflint)"
echo "Environment: $ENVIRONMENT"
echo ""

echo "→ terraform fmt"
bash "$ROOT_DIR/scripts/fmt.sh"
echo "fmt complete"
echo ""

echo "→ terraform validate"
cd "$ENV_DIR"
terraform init -backend=false -input=false >/dev/null
terraform validate
echo "terraform validate passed"
echo ""

echo "→ tflint"
if ! command -v tflint >/dev/null 2>&1; then
  echo "tflint is not installed"
  echo "Install: https://github.com/terraform-linters/tflint"
  exit 1
fi

cd "$ROOT_DIR"
tflint
echo "tflint passed"
echo ""

echo "validate complete for environment: $ENVIRONMENT"
