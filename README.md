# template-terraform-boilerplate
Reusable Terraform boilerplate repo: a clean starter structure for modules, multi environments, and CI-ready workflow.

---

## What you get (the template contract)

- **Clear environment roots** under `infra/env/` (dev/prod are explicit)
- **Reusable modules** under `infra/modules/` (inputs in, outputs out)
- A consistent local workflow via `infra/scripts/`:
  - `fmt → validate (includes tflint) → plan → apply`
- A GitHub Actions workflow that:
  - runs **validate + plan** on pull requests
  - runs **apply** in a controlled way (dev can be automated, prod can be gated via approvals)

---

## Prerequisites

  Install these locally:

  - Terraform CLI
  - AWS CLI
  - `jq` (used by `whoami.sh`)
  - `tflint` (used by `validate.sh`)

---


