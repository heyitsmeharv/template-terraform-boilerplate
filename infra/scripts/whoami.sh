#!/usr/bin/env bash
set -euo pipefail

# whoami.sh
# - Prints the current AWS identity (account ID + principal ARN) for the *current shell session*.
# - This is a safety check before running plan/apply, especially after switching AWS_PROFILE.
# - Runs in Git Bash (Windows) or any Bash shell where aws is available on PATH.
#
# Usage:
#   bash infra/scripts/whoami.sh
#
# Output:
# - If jq is installed: pretty-printed JSON
# - If jq is not installed: raw JSON
#
# Requirements:
# - aws CLI must be installed and discoverable via PATH in this shell
# - jq is optional (only used for formatting)

if ! command -v aws >/dev/null 2>&1; then
  echo "aws CLI is required for this script."
  echo "Run: bash infra/scripts/prereqs.sh"
  exit 1
fi

if command -v jq >/dev/null 2>&1; then
  aws sts get-caller-identity | jq
else
  aws sts get-caller-identity
fi
