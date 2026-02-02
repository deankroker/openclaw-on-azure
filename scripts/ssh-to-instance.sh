#!/bin/bash
# SSH into an OpenClaw VMSS instance
source "$(dirname "$0")/common.sh"

INSTANCE_INDEX="${1:-0}"
ADMIN_USER="${ADMIN_USERNAME:-openclaw}"

check_prerequisites

VMSS_NAME=$(get_vmss_name)
if [[ -z "$VMSS_NAME" ]]; then
  echo "ERROR: No VMSS found in resource group $RESOURCE_GROUP"
  exit 1
fi

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
