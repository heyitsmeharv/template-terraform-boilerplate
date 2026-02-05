#!/usr/bin/env bash
set -euo pipefail

# fmt.sh
# - Formats Terraform code under infra/ recursively.
# - Keeps diffs clean and matches what CI enforces.
#
# Usage:
#   infra/scripts/fmt.sh

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

terraform fmt -recursive
echo "fmt complete"