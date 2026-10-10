#!/usr/bin/env bash
# VM:n startas kort för tester och frigörs även om en kontroll misslyckas.
set -euo pipefail
BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$BASE/config.local.sh"
: "${SUBSCRIPTION_ID:?}" "${TENANT_ID:?}" "${RESOURCE_GROUP:?}"
az account set --subscription "$SUBSCRIPTION_ID"
[[ "$(az account show --query tenantId -o tsv)" == "$TENANT_ID" ]] || { echo 'Fel tenant.' >&2; exit 1; }
VM=vm-novatrix-web
cleanup() { az vm deallocate -g "$RESOURCE_GROUP" -n "$VM" -o none; }
trap cleanup EXIT
az vm start -g "$RESOURCE_GROUP" -n "$VM" -o none
LOCAL_IP="$(az network nic show -g "$RESOURCE_GROUP" -n nic-novatrix-web --query 'ipConfigurations[0].privateIPAddress' -o tsv)"
for spec in '80:Allow' '443:Allow' '22:Deny' '8080:Deny'; do
  port="${spec%%:*}"; expected="${spec#*:}"
  result="$(az network watcher test-ip-flow -g "$RESOURCE_GROUP" --vm "$VM" --nic nic-novatrix-web --direction Inbound --protocol TCP --local "$LOCAL_IP:$port" --remote '8.8.8.8:53000' -o json)"
  echo "PORT $port: $result"
  access="$(printf '%s' "$result" | python -c 'import json,sys; print(json.load(sys.stdin)["access"])')"
  [[ "$access" == "$expected" ]] || { echo "Oväntat resultat för port $port." >&2; exit 1; }
done
for spec in '443:Allow' '80:Deny'; do
  port="${spec%%:*}"; expected="${spec#*:}"
  result="$(az network watcher test-ip-flow -g "$RESOURCE_GROUP" --vm "$VM" --nic nic-novatrix-web --direction Outbound --protocol TCP --local "$LOCAL_IP:53000" --remote "8.8.8.8:$port" -o json)"
  echo "UTGÅENDE PORT $port: $result"
  access="$(printf '%s' "$result" | python -c 'import json,sys; print(json.load(sys.stdin)["access"])')"
  [[ "$access" == "$expected" ]] || { echo "Oväntat utgående resultat för port $port." >&2; exit 1; }
done
PUBLIC_IP="$(az network public-ip show -g "$RESOURCE_GROUP" -n pip-novatrix-web --query ipAddress -o tsv)"
BODY="$(curl --fail --retry 12 --retry-delay 5 --retry-connrefused --connect-timeout 5 --max-time 10 "http://$PUBLIC_IP")"
[[ "$BODY" == *Novatrix* ]] || { echo 'HTTP svarar men Novatrix-innehållet saknas.' >&2; exit 1; }
echo 'HTTP: Novatrix-sidan verifierad via publik IP.'
echo 'HTTPS: port 443 är tillåten enligt NSG-testet; TLS-webbtjänsten har inte verifierats.'
if [[ "${EVIDENCE_PAUSE_SECONDS:-0}" =~ ^[0-9]+$ ]] && (( ${EVIDENCE_PAUSE_SECONDS:-0} > 0 && ${EVIDENCE_PAUSE_SECONDS:-0} <= 60 )); then
  echo 'Kort paus för att spara bildbevis. VM:n frigörs därefter.'
  sleep "$EVIDENCE_PAUSE_SECONDS"
fi
