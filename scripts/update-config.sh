#!/bin/bash
# Push updated config to all VMSS instances
source "$(dirname "$0")/common.sh"

check_prerequisites

VMSS_NAME=$(get_vmss_name)
if [[ -z "$VMSS_NAME" ]]; then
  echo "ERROR: No VMSS found in resource group $RESOURCE_GROUP"
  exit 1
fi

CONFIG_FILE="${1:-$PROJECT_ROOT/config/openclaw.template.json}"
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "ERROR: Config file not found: $CONFIG_FILE"
  exit 1
fi

CONFIG_CONTENT=$(cat "$CONFIG_FILE" | jq -c .)
ADMIN_USER="${ADMIN_USERNAME:-openclaw}"

echo "Pushing config to all instances of $VMSS_NAME..."

INSTANCE_IDS=$(az vmss list-instances -g "$RESOURCE_GROUP" -n "$VMSS_NAME" --query "[].instanceId" -o tsv)

for INSTANCE_ID in $INSTANCE_IDS; do
  echo "Updating instance $INSTANCE_ID..."
  az vmss run-command invoke \
    -g "$RESOURCE_GROUP" \
    -n "$VMSS_NAME" \
    --instance-id "$INSTANCE_ID" \
    --command-id RunShellScript \
    --scripts "echo '${CONFIG_CONTENT}' | jq . > /home/${ADMIN_USER}/.openclaw/openclaw.json && sudo -u ${ADMIN_USER} XDG_RUNTIME_DIR=/run/user/\$(id -u ${ADMIN_USER}) systemctl --user restart openclaw-gateway" \
    --output none
  echo "  Instance $INSTANCE_ID updated."
done

echo "Config pushed to all instances."
