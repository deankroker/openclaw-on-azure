#!/bin/bash
# Destroy all OpenClaw Azure resources
source "$(dirname "$0")/common.sh"

FORCE=false
if [[ "${1:-}" == "--force" ]]; then
  FORCE=true
fi

if [[ "$FORCE" != "true" ]]; then
  echo "This will DELETE the resource group '$RESOURCE_GROUP' and ALL resources in it."
  read -rp "Type the resource group name to confirm: " CONFIRM
  if [[ "$CONFIRM" != "$RESOURCE_GROUP" ]]; then
    echo "Aborted."
    exit 1
  fi
fi

echo "Deleting resource group $RESOURCE_GROUP..."
az group delete --name "$RESOURCE_GROUP" --yes --no-wait
echo "Deletion initiated (running in background)."
