# Contributing

Thanks for your interest in improving OpenClaw on Azure.

## Prerequisites

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) with Bicep (`az bicep install`)
- [jq](https://jqlang.github.io/jq/download/)

## Getting started

```bash
git clone https://github.com/<your-fork>/openclaw-on-azure.git
cd openclaw-on-azure
```

## Validating Bicep changes

Before opening a PR, make sure your changes compile and lint cleanly:

```bash
az bicep build --file infra/main.bicep
az bicep lint --file infra/main.bicep
```

Linting rules are defined in `infra/bicepconfig.json`. The CI pipeline runs both checks automatically on every PR.

## Pull request expectations

- Describe what you changed and why.
- Bicep build and lint must pass (CI will check this).
- If you add a new parameter, make sure it has a `@description` decorator.
- If you change deployment behavior, update the README.

## Project structure

```
infra/
  main.bicep              # Orchestrator — wires modules together
  main.bicepparam         # Infrastructure parameters (vm size, instance count, etc.)
  modules/
    network.bicep          # VNet, subnet, NSG
    keyvault.bicep         # Key Vault + secrets
    vmss.bicep             # VM Scale Set + cloud-init + RBAC
  cloud-init/
    cloud-init.yaml        # VM bootstrap script
scripts/
  deploy.sh               # Main deployment entry point
  teardown.sh              # Resource group cleanup
  ssh-to-instance.sh       # SSH into a VMSS instance
  scale.sh                 # Scale instance count
  update-config.sh         # Push config to running VMs
  common.sh                # Shared bash utilities
```
