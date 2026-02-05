#!/usr/bin/env bash
set -euo pipefail

# use-env.sh
# - Switches local AWS context by setting AWS_PROFILE=<aws-account>.
# - Use with "source" so the variable persists in your current shell session.
#
# Usage:
#   source infra/scripts/use-env.sh <aws-account>
#
# Notes:
# - Assumes AWS profiles are configured in ~/.aws/config
# - Region is set here for convenience and can be overridden

ENVIRONMENT="${1:-}"
if [ -z "$ENVIRONMENT" ]; then
  echo "Usage: source infra/scripts/use-env.sh <aws-account>"
  return 1 2>/dev/null || exit 1
fi

export AWS_PROFILE="$ENVIRONMENT"

export AWS_REGION="${AWS_REGION:-eu-west-2}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-$AWS_REGION}"

echo "Switched AWS context"
echo "AWS_PROFILE=$AWS_PROFILE"
echo ""
echo "Next:"
echo "  cd infra/env/$ENVIRONMENT"
echo "  terraform init -backend-config=../../backend.hcl"
echo "  terraform plan -var-file=env.tfvars"