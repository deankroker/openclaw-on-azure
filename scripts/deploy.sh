#!/bin/bash
# Deploy OpenClaw on Azure VMSS
source "$(dirname "$0")/common.sh"

usage() {
  echo "Usage: $0 [options]"
  echo ""
  echo "Infrastructure parameters are defined in infra/main.bicepparam."
  echo "Deployment overrides (resource group, location, SSH key path) can be"
  echo "set via a .env file in the project root."
  echo ""
  echo "Options:"
  echo "  --open         Allow inbound traffic from any IP (default: restrict to your IP)"
  echo "  --help, -h     Show this help message"
}

OPEN_ACCESS=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --open) OPEN_ACCESS=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

check_prerequisites

# Validate inputs
if [[ ! -f "$SSH_KEY_PATH" ]]; then
  echo "ERROR: SSH public key not found at $SSH_KEY_PATH"
  exit 1
fi

if [[ ! -f "$SECRETS_FILE" ]]; then
  echo "ERROR: Secrets file not found at $SECRETS_FILE"
  exit 1
fi

# Determine source CIDR for NSG rules
if [[ "$OPEN_ACCESS" == true ]]; then
  SOURCE_CIDR="*"
  echo ""
  echo "WARNING: Deploying with NSG rules open to all IPs (*)"
  echo "         This is not recommended for production use."
  echo ""
else
  echo "Detecting your public IP..."
  MY_IP=$(curl -s --max-time 5 https://api.ipify.org)
  if [[ -n "$MY_IP" && "$MY_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    SOURCE_CIDR="${MY_IP}/32"
    echo "NSG rules will be restricted to your IP: $MY_IP"
  else
    echo "WARNING: Could not detect your public IP. Falling back to open access (*)."
    echo "         Re-run with an explicit CIDR or fix your network and try again."
    SOURCE_CIDR="*"
  fi
fi

SSH_KEY=$(cat "$SSH_KEY_PATH")
SECRETS=$(cat "$SECRETS_FILE")

echo ""
echo "=== Deploying OpenClaw ==="
echo "Resource Group: $RESOURCE_GROUP"
echo "Location:       $LOCATION"
echo "Source CIDR:    $SOURCE_CIDR"
echo ""

# Create resource group
echo "Creating resource group..."
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none

# Build deployment parameters
DEPLOY_PARAMS=(
  --resource-group "$RESOURCE_GROUP"
  --template-file "$PROJECT_ROOT/infra/main.bicep"
  --parameters "$PROJECT_ROOT/infra/main.bicepparam"
  --parameters sshPublicKey="$SSH_KEY"
  --parameters openclawSecrets="$SECRETS"
  --parameters sshSourceCidr="$SOURCE_CIDR"
  --parameters gatewaySourceCidr="$SOURCE_CIDR"
)

# Deploy
echo "Deploying infrastructure..."
RESULT=$(az deployment group create "${DEPLOY_PARAMS[@]}" --output json)

# Print outputs
echo ""
echo "=== Deployment Complete ==="
echo "$RESULT" | jq -r '.properties.outputs | to_entries[] | "\(.key): \(.value.value)"'
echo ""
echo "SSH into an instance with: ./scripts/ssh-to-instance.sh"
