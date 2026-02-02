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

# Validate secrets file
if [[ ! -f "$SECRETS_FILE" ]]; then
  echo "ERROR: Secrets file not found at $SECRETS_FILE"
  exit 1
fi

# SSH key is optional — read it if available, otherwise empty string
SSH_KEY=""
if [[ -f "$SSH_KEY_PATH" ]]; then
  SSH_KEY=$(cat "$SSH_KEY_PATH")
  echo "SSH public key found at $SSH_KEY_PATH"
else
  echo "No SSH key at $SSH_KEY_PATH — skipping SSH key auth (Entra ID only)"
fi

# Team mode: resolve Entra ID object IDs from team.json
TEAM_MODE=false
TEAM_OBJECT_IDS=()
TEAM_EMAILS=()
INSTANCE_COUNT_OVERRIDE=""

if [[ -f "$TEAM_FILE" ]]; then
  TEAM_MODE=true
  echo ""
  echo "=== Team mode ==="
  echo "Reading team members from $TEAM_FILE..."

  TEAM_EMAILS=($(jq -r '.members[].email' "$TEAM_FILE"))

  if [[ ${#TEAM_EMAILS[@]} -eq 0 ]]; then
    echo "ERROR: No members found in $TEAM_FILE"
    exit 1
  fi

  echo "Found ${#TEAM_EMAILS[@]} team member(s). Resolving Entra ID object IDs..."

  for email in "${TEAM_EMAILS[@]}"; do
    object_id=$(az ad user show --id "$email" --query id -o tsv 2>/dev/null || true)
    if [[ -n "$object_id" ]]; then
      TEAM_OBJECT_IDS+=("$object_id")
      echo "  $email -> $object_id"
    else
      echo "  WARNING: Could not resolve $email — skipping (user may not exist in this tenant)"
      TEAM_OBJECT_IDS+=("")
    fi
  done

  # Filter out empty entries for the Bicep parameter
  RESOLVED_IDS=()
  for id in "${TEAM_OBJECT_IDS[@]}"; do
    if [[ -n "$id" ]]; then
      RESOLVED_IDS+=("$id")
    fi
  done

  if [[ ${#RESOLVED_IDS[@]} -eq 0 ]]; then
    echo "ERROR: Could not resolve any team member emails to Entra ID object IDs"
    exit 1
  fi

  INSTANCE_COUNT_OVERRIDE="${#TEAM_EMAILS[@]}"
  echo "Instance count auto-set to $INSTANCE_COUNT_OVERRIDE (one per team member)"
fi

# Determine source CIDRs for NSG rules
if [[ "$OPEN_ACCESS" == true ]]; then
  SSH_CIDR="*"
  GATEWAY_CIDR="*"
  echo ""
  echo "WARNING: Deploying with NSG rules open to all IPs (*)"
  echo "         This is not recommended for production use."
  echo ""
elif [[ "$TEAM_MODE" == true ]]; then
  # Team mode: SSH open to all (Entra ID is the auth boundary), gateway locked to deployer IP
  SSH_CIDR="*"
  echo ""
  echo "Team mode: SSH NSG open to all IPs (Entra ID authentication is the security boundary)"
  echo "Detecting your public IP for gateway access..."
  MY_IP=$(curl -s --max-time 5 https://api.ipify.org)
  if [[ -n "$MY_IP" && "$MY_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    GATEWAY_CIDR="${MY_IP}/32"
    echo "Gateway NSG restricted to your IP: $MY_IP"
  else
    echo "WARNING: Could not detect your public IP. Gateway access open to all (*)."
    GATEWAY_CIDR="*"
  fi
  echo ""
else
  echo "Detecting your public IP..."
  MY_IP=$(curl -s --max-time 5 https://api.ipify.org)
  if [[ -n "$MY_IP" && "$MY_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    SSH_CIDR="${MY_IP}/32"
    GATEWAY_CIDR="${MY_IP}/32"
    echo "NSG rules will be restricted to your IP: $MY_IP"
  else
    echo "WARNING: Could not detect your public IP. Falling back to open access (*)."
    echo "         Re-run with an explicit CIDR or fix your network and try again."
    SSH_CIDR="*"
    GATEWAY_CIDR="*"
  fi
fi

SECRETS=$(cat "$SECRETS_FILE")

echo ""
echo "=== Deploying OpenClaw ==="
echo "Resource Group: $RESOURCE_GROUP"
echo "Location:       $LOCATION"
echo "SSH CIDR:       $SSH_CIDR"
echo "Gateway CIDR:   $GATEWAY_CIDR"
if [[ "$TEAM_MODE" == true ]]; then
  echo "Team mode:      yes (${#TEAM_EMAILS[@]} members)"
fi
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
  --parameters sshSourceCidr="$SSH_CIDR"
  --parameters gatewaySourceCidr="$GATEWAY_CIDR"
)

# Add team-specific parameters
if [[ "$TEAM_MODE" == true ]]; then
  # Build JSON array of object IDs for Bicep
  OBJECT_IDS_JSON=$(printf '%s\n' "${RESOLVED_IDS[@]}" | jq -R . | jq -s .)
  DEPLOY_PARAMS+=(--parameters "vmUserLoginObjectIds=$OBJECT_IDS_JSON")

  if [[ -n "$INSTANCE_COUNT_OVERRIDE" ]]; then
    DEPLOY_PARAMS+=(--parameters "instanceCount=$INSTANCE_COUNT_OVERRIDE")
  fi
fi

# Deploy
echo "Deploying infrastructure..."
RESULT=$(az deployment group create "${DEPLOY_PARAMS[@]}" --output json)

# Print outputs
echo ""
echo "=== Deployment Complete ==="
echo "$RESULT" | jq -r '.properties.outputs | to_entries[] | "\(.key): \(.value.value)"'

if [[ "$TEAM_MODE" == true ]]; then
  echo ""
  echo "=== Team Access ==="
  echo ""
  echo "Waiting for instance names..."
  VMSS_NAME=$(get_vmss_name)
  INSTANCE_NAMES=($(get_instance_names))

  echo ""
  printf "%-30s %-40s %s\n" "MEMBER" "INSTANCE" "CONNECT COMMAND"
  printf "%-30s %-40s %s\n" "------" "--------" "---------------"
  for i in "${!TEAM_EMAILS[@]}"; do
    email="${TEAM_EMAILS[$i]}"
    if [[ $i -lt ${#INSTANCE_NAMES[@]} ]]; then
      name="${INSTANCE_NAMES[$i]}"
      cmd="az ssh vm --resource-group $RESOURCE_GROUP --name $name"
    else
      name="(pending)"
      cmd="(instance not yet provisioned)"
    fi
    printf "%-30s %-40s %s\n" "$email" "$name" "$cmd"
  done
  echo ""
  echo "NOTE: Entra ID RBAC propagation can take 5-10 minutes."
  echo "      Team members need: az extension add --name ssh"
else
  echo ""
  echo "SSH into an instance with: ./scripts/ssh-to-instance.sh"
fi
