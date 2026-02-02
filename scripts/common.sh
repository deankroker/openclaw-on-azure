#!/bin/bash
# Shared functions and variables for OpenClaw deployment scripts
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load .env if it exists
if [[ -f "$PROJECT_ROOT/.env" ]]; then
  set -a
  source "$PROJECT_ROOT/.env"
  set +a
fi

# Defaults (infrastructure params live in infra/main.bicepparam)
RESOURCE_GROUP="${RESOURCE_GROUP:-openclaw-rg}"
LOCATION="${LOCATION:-eastus2}"
SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/id_rsa.pub}"
SECRETS_FILE="${SECRETS_FILE:-$PROJECT_ROOT/secrets.json}"
TEAM_FILE="${TEAM_FILE:-$PROJECT_ROOT/team.json}"
ADMIN_USERNAME="${ADMIN_USERNAME:-openclaw}"

# Set subscription if specified
if [[ -n "${AZURE_SUBSCRIPTION:-}" ]]; then
  az account set --subscription "$AZURE_SUBSCRIPTION"
fi

check_prerequisites() {
  local missing=0
  for cmd in az jq; do
    if ! command -v "$cmd" &> /dev/null; then
      echo "ERROR: '$cmd' is required but not installed."
      missing=1
    fi
  done
  if [[ $missing -eq 1 ]]; then
    exit 1
  fi

  # Check Azure login
  if ! az account show &> /dev/null; then
    echo "ERROR: Not logged in to Azure. Run 'az login' first."
    exit 1
  fi
}

get_vmss_name() {
  az vmss list -g "$RESOURCE_GROUP" --query "[0].name" -o tsv 2>/dev/null
}

get_instance_ips() {
  local vmss_name
  vmss_name=$(get_vmss_name)
  if [[ -z "$vmss_name" ]]; then
    echo "ERROR: No VMSS found in resource group $RESOURCE_GROUP"
    return 1
  fi
  az vmss list-instance-public-ips -g "$RESOURCE_GROUP" -n "$vmss_name" --query "[].ipAddress" -o tsv
}

get_instance_names() {
  local vmss_name
  vmss_name=$(get_vmss_name)
  if [[ -z "$vmss_name" ]]; then
    echo "ERROR: No VMSS found in resource group $RESOURCE_GROUP"
    return 1
  fi
  az vmss list-instances -g "$RESOURCE_GROUP" -n "$vmss_name" --query "[].name" -o tsv
}
