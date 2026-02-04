#!/usr/bin/env bash
set -euo pipefail

# prereqs.sh
# - Verifies required tooling is available *in this Git Bash shell* (i.e., discoverable via PATH).
# - This repo standardises on Git Bash to avoid cmd/powershell/Linux differences.
# - This script does not install anything; it only checks and prints versions.
#
# Usage:
#   bash infra/scripts/prereqs.sh
#
# Requirements:
# - Run in Git Bash (Windows) or any Bash shell with the tools on PATH.
#
# Notes:
# - If something is missing, install it and then restart Git Bash so PATH updates apply.

need() {
  local bin="$1"
  local hint="$2"

  if ! command -v "$bin" >/dev/null 2>&1; then
    echo ""
    echo "Missing: $bin"
    echo "Fix: $hint"
    echo ""
    exit 1
  fi
}

echo "Checking prerequisites in Git Bash..."
echo ""

need terraform "Install Terraform and ensure it's on PATH for Git Bash"
need aws       "Install AWS CLI v2 and ensure it's on PATH for Git Bash"
need jq        "Install jq and ensure it's on PATH for Git Bash (optional for pretty output, but required by this template)"
need tflint    "Install tflint and ensure it's on PATH for Git Bash"
need node      "Install Node.js (LTS) and ensure it's on PATH for Git Bash"
need npm       "npm should come with Node.js (LTS)"

echo "All required tools are available."
echo ""

echo "terraform: $(terraform version | head -n 1)"
echo "aws:       $(aws --version 2>&1)"
echo "jq:        $(jq --version)"
echo "tflint:    $(tflint --version | head -n 1)"
echo "node:      $(node --version)"
echo "npm:       $(npm --version)"
echo