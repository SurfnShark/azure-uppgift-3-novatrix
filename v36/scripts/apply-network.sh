#!/usr/bin/env bash
set -euo pipefail
BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$BASE/config.local.sh"
: "${SUBSCRIPTION_ID:?}" "${TENANT_ID:?}" "${RESOURCE_GROUP:?}"
az account set --subscription "$SUBSCRIPTION_ID"
[[ "$(az account show --query tenantId -o tsv)" == "$TENANT_ID" ]] || { echo 'Fel tenant.' >&2; exit 1; }
[[ "$(az account show --query state -o tsv)" == Enabled ]] || { echo 'Prenumerationen måste vara aktiv.' >&2; exit 1; }
[[ "$RESOURCE_GROUP" == rg-novatrix ]] || { echo 'Mallen gäller rg-novatrix.' >&2; exit 1; }
[[ "$(az network vnet show -g "$RESOURCE_GROUP" -n vnet-novatrix --query 'addressSpace.addressPrefixes[0]' -o tsv)" == 10.10.0.0/16 ]] || { echo 'Oväntad adressrymd.' >&2; exit 1; }
[[ "$(az network vnet show -g "$RESOURCE_GROUP" -n vnet-novatrix --query 'length(addressSpace.addressPrefixes)' -o tsv)" == 1 ]] || { echo 'Fler adressrymder finns. Granska mallen först.' >&2; exit 1; }
UNKNOWN_SUBNET_QUERY="length([?name!='snet-novatrix-web' && name!='snet-novatrix-private'])"
[[ "$(az network vnet subnet list -g "$RESOURCE_GROUP" --vnet-name vnet-novatrix --query "$UNKNOWN_SUBNET_QUERY" -o tsv)" == 0 ]] || { echo 'Andra subnät finns. Mallen måste utökas innan körning.' >&2; exit 1; }
[[ "$(az network vnet subnet show -g "$RESOURCE_GROUP" --vnet-name vnet-novatrix -n snet-novatrix-web --query addressPrefix -o tsv)" == 10.10.1.0/24 ]] || { echo 'Oväntat webbsubnät.' >&2; exit 1; }
NIC_SUBNET="$(az network nic show -g "$RESOURCE_GROUP" -n nic-novatrix-web --query 'ipConfigurations[0].subnet.id' -o tsv)"
EXPECTED="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Network/virtualNetworks/vnet-novatrix/subnets/snet-novatrix-web"
[[ "${NIC_SUBNET,,}" == "${EXPECTED,,}" ]] || { echo 'Webbserverns nätverkskort ligger i ett annat subnät.' >&2; exit 1; }
# Spara nuläget privat så att tidigare kopplingar kan återställas vid behov.
mkdir -p "$BASE/evidence"
az network nic show -g "$RESOURCE_GROUP" -n nic-novatrix-web > "$BASE/evidence/nic-before.json"
az network vnet subnet list -g "$RESOURCE_GROUP" --vnet-name vnet-novatrix > "$BASE/evidence/subnets-before.json"
az deployment group what-if -g "$RESOURCE_GROUP" --template-file "$BASE/network/network.json"
read -r -p 'Tillämpa nätverksändringarna? Skriv JA: ' answer
[[ "$answer" == JA ]] || { echo 'Avbrutet utan driftsättning.'; exit 0; }
az deployment group create -g "$RESOURCE_GROUP" --name novatrix-v36-network --mode Incremental --template-file "$BASE/network/network.json" --query properties.provisioningState -o tsv
az network nic update -g "$RESOURCE_GROUP" -n nic-novatrix-web --network-security-group nsg-novatrix-web-v36 -o none
echo 'Nätverket tillämpat. Webbservern har inte startats av detta skript.'
