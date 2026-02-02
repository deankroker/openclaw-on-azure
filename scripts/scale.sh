#!/bin/bash
# Scale VMSS instance count
source "$(dirname "$0")/common.sh"

usage() {
  echo "Usage: $0 --count N"
}

COUNT=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --count|-c) COUNT="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

if [[ -z "$COUNT" ]]; then
  echo "ERROR: --count is required"
  usage
  exit 1
fi

check_prerequisites

VMSS_NAME=$(get_vmss_name)
if [[ -z "$VMSS_NAME" ]]; then
  echo "ERROR: No VMSS found in resource group $RESOURCE_GROUP"
  exit 1
fi

echo "Scaling $VMSS_NAME to $COUNT instances..."
az vmss scale -g "$RESOURCE_GROUP" -n "$VMSS_NAME" --new-capacity "$COUNT" --output none
echo "Scaled to $COUNT instances."
