# GitHub Deploy Runner (ARC)

This folder contains resources to run GitHub Actions deploy jobs inside the cluster via Actions Runner Controller (ARC).

## What it deploys

- `01-deploy-runner-rbac.yaml`
  - `ServiceAccount` in `arc-runners`: `gha-deploy-runner`
  - Minimal `Role`/`RoleBinding` in `palad` namespace to restart and watch:
    - `deployment/web`
    - `deployment/worker-ruby`
    - `deployment/mcp`
  - Migration job permissions in `palad` (`batch/jobs`)
- `02-deploy-runner-rbac-staging.yaml`
  - Minimal `Role`/`RoleBinding` in `palad-staging` namespace to restart and watch:
    - `deployment/web`
    - `deployment/worker-ruby`
    - `deployment/mcp`
  - Migration job permissions in `palad-staging` (`batch/jobs`)
- `values-runner-scale-set.yaml`
  - Runner scale set name: `palad-deploy-runner` (used by workflow `runs-on`)

## One-time setup

1. Create GitHub auth secret (prefer GitHub App credentials):
   - copy `00-github-auth-secret.example.yaml`, fill values, apply it.
2. Install ARC controller + runner scale set + deploy RBAC:
   - `make kube-arc-install`

## Notes

- Deploy workflow uses `runs-on: palad-deploy-runner`.
- No Terraform changes are required for deploy runner RBAC inside the cluster.
