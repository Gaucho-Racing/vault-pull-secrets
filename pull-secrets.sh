#!/usr/bin/env bash
set +x
set -euo pipefail

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "$1 is required to pull Vault secrets." >&2
    exit 1
  fi
}

require_command curl
require_command jq

escape_workflow_command_value() {
  local value="$1"
  value="${value//'%'/'%25'}"
  value="${value//$'\r'/'%0D'}"
  value="${value//$'\n'/'%0A'}"
  printf '%s' "$value"
}

add_mask() {
  local value="$1"
  if [ -z "$value" ]; then
    return
  fi
  printf '::add-mask::%s\n' "$(escape_workflow_command_value "$value")"
}

mask_env_file_values() {
  local env_file="$1"
  local line delimiter value has_value

  while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" == *"<<"* ]]; then
      delimiter="${line#*<<}"
      value=""
      has_value=false

      while IFS= read -r line; do
        if [[ "$line" == "$delimiter" ]]; then
          add_mask "$value"
          break
        fi
        if [[ "$has_value" == true ]]; then
          value+=$'\n'
        fi
        value+="$line"
        has_value=true
      done
    elif [[ "$line" == *=* ]]; then
      add_mask "${line#*=}"
    fi
  done < "$env_file"
}

if [ -z "${VAULT_URL:-}" ]; then
  echo "vault_url is required." >&2
  exit 1
fi

if [ -z "${VAULT_SECRETS:-}" ]; then
  echo "secrets is required." >&2
  exit 1
fi

if [ -z "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}" ] || [ -z "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ]; then
  echo "GitHub OIDC token request variables are unavailable. Grant this job permissions.id-token: write." >&2
  exit 1
fi

if [ -z "${GITHUB_ENV:-}" ]; then
  echo "GITHUB_ENV is unavailable." >&2
  exit 1
fi

vault_base_url="${VAULT_URL%/}"
vault_api_url="${vault_base_url%/api}/api"

encoded_audience="$(jq -nr --arg value "${VAULT_AUDIENCE:-}" '$value|@uri')"
oidc_response="$(
  curl -fsS \
    -H "Authorization: Bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" \
    "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=${encoded_audience}"
)"
oidc_token="$(jq -r '.value // empty' <<< "$oidc_response")"

if [ -z "$oidc_token" ]; then
  echo "GitHub OIDC response did not include a token." >&2
  exit 1
fi

requested_secrets="$(
  jq -Rsc '[split("\n")[] | split(",")[] | gsub("^\\s+|\\s+$"; "") | select(length > 0)]' <<< "$VAULT_SECRETS"
)"

if [ "$requested_secrets" = "[]" ]; then
  echo "At least one Vault app secret selector is required." >&2
  exit 1
fi

payload="$(jq -n --arg token "$oidc_token" --argjson secrets "$requested_secrets" '{token: $token, secrets: $secrets}')"
response_file="$(mktemp)"
status_code="$(
  curl -sS \
    -o "$response_file" \
    -w "%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    --data "$payload" \
    "${vault_api_url}/integrations/github/actions/env"
)"

if [[ "$status_code" -lt 200 || "$status_code" -ge 300 ]]; then
  echo "Vault returned HTTP ${status_code}." >&2
  jq -r '.error // empty' < "$response_file" >&2 || true
  rm -f "$response_file"
  exit 1
fi

mask_env_file_values "$response_file"
cat "$response_file" >> "$GITHUB_ENV"
rm -f "$response_file"
