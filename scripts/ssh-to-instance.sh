#!/bin/bash
# SSH into an OpenClaw VMSS instance
source "$(dirname "$0")/common.sh"

usage() {
  echo "Usage: $0 [options] [instance-index]"
  echo ""
  echo "Options:"
  echo "  --entra        Use Entra ID auth (az ssh vm) instead of SSH key"
  echo "  --help, -h     Show this help message"
  echo ""
  echo "If no SSH key exists locally, defaults to --entra automatically."
}

USE_ENTRA=false
INSTANCE_INDEX=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --entra) USE_ENTRA=true; shift ;;
    --help|-h) usage; exit 0 ;;
    -*) echo "Unknown option: $1"; usage; exit 1 ;;
    *) INSTANCE_INDEX="$1"; shift ;;
  esac
done

INSTANCE_INDEX="${INSTANCE_INDEX:-0}"

# Auto-detect: if no SSH key exists locally, default to Entra
if [[ "$USE_ENTRA" == false && ! -f "$SSH_KEY_PATH" ]]; then
  echo "No SSH key found at $SSH_KEY_PATH — using Entra ID auth"
  USE_ENTRA=true
fi

check_prerequisites

VMSS_NAME=$(get_vmss_name)
if [[ -z "$VMSS_NAME" ]]; then
  echo "ERROR: No VMSS found in resource group $RESOURCE_GROUP"
  exit 1
fi

if [[ "$USE_ENTRA" == true ]]; then
  NAMES=($(get_instance_names))
  if [[ ${#NAMES[@]} -eq 0 ]]; then
    echo "ERROR: No instances found"
    exit 1
  fi

  if [[ $INSTANCE_INDEX -ge ${#NAMES[@]} ]]; then
    echo "ERROR: Instance index $INSTANCE_INDEX out of range (${#NAMES[@]} instances available)"
    exit 1
  fi

  NAME="${NAMES[$INSTANCE_INDEX]}"
  echo "Connecting to instance $INSTANCE_INDEX ($NAME) via Entra ID..."
  az ssh vm --resource-group "$RESOURCE_GROUP" --name "$NAME"
else
  ADMIN_USER="${ADMIN_USERNAME:-openclaw}"

  IPS=($(get_instance_ips))
  if [[ ${#IPS[@]} -eq 0 ]]; then
    echo "ERROR: No instances found with public IPs"
    exit 1
  fi

  if [[ $INSTANCE_INDEX -ge ${#IPS[@]} ]]; then
    echo "ERROR: Instance index $INSTANCE_INDEX out of range (${#IPS[@]} instances available)"
    exit 1
  fi

  IP="${IPS[$INSTANCE_INDEX]}"
  echo "Connecting to instance $INSTANCE_INDEX at $IP..."
  ssh -o StrictHostKeyChecking=accept-new "$ADMIN_USER@$IP"
fi
