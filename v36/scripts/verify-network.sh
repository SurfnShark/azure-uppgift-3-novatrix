#!/usr/bin/env bash
set -euo pipefail
BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$BASE/config.local.sh"
: "${SUBSCRIPTION_ID:?}" "${TENANT_ID:?}" "${RESOURCE_GROUP:?}"
az account set --subscription "$SUBSCRIPTION_ID"
[[ "$(az account show --query tenantId -o tsv)" == "$TENANT_ID" ]] || { echo 'Fel tenant.' >&2; exit 1; }
mkdir -p "$BASE/evidence"
az network vnet subnet list -g "$RESOURCE_GROUP" --vnet-name vnet-novatrix --query '[].{Subnet:name,Address:addressPrefix,NSG:networkSecurityGroup.id,DefaultOutbound:defaultOutboundAccess}' -o table
az network nic show -g "$RESOURCE_GROUP" -n nic-novatrix-web --query '{Subnet:ipConfigurations[0].subnet.id,NSG:networkSecurityGroup.id}' -o json
for nsg in nsg-novatrix-web-v36 nsg-novatrix-private; do
  echo "REGLER: $nsg"
  az network nsg rule list -g "$RESOURCE_GROUP" --nsg-name "$nsg" --query '[].{Name:name,Priority:priority,Direction:direction,Access:access,Source:sourceAddressPrefix,Destination:destinationAddressPrefix,Ports:destinationPortRange || destinationPortRanges}' -o json
done
echo 'Konfiguration inventerad. Faktiska trafiktester körs separat medan VM:n är igång.'
