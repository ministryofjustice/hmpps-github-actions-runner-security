#!/usr/bin/env bash
set -euo pipefail

# Required env:
#   GH_APP_ID               e.g. 123456
#   GH_APP_PRIVATE_KEY_PATH     e.g. /var/run/secrets/github-app/private-key.pem
#   GH_ORG                  e.g. ministryofjustice
#
# Optional:
#   GH_INSTALLATION_ID      if not set, script discovers it from GH_ORG
#   GH_REPO                 only needed if you prefer repo-based installation lookup

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1" >&2; exit 1; }
}

require_var() {
  local name="$1"
  [[ -n "${!name:-}" ]] || { echo "Missing required env var: $name" >&2; exit 1; }
}

require_cmd curl
require_cmd jq
require_cmd openssl

require_var GH_APP_ID
require_var GH_APP_PRIVATE_KEY_PATH
require_var GH_ORG

if [[ ! -r "$GH_APP_PRIVATE_KEY_PATH" ]]; then
  echo "Private key file not readable: $GH_APP_PRIVATE_KEY_PATH" >&2
  exit 1
fi

b64url() {
  openssl base64 -A | tr '+/' '-_' | tr -d '='
}

now="$(date +%s)"
iat="$((now - 60))"
exp="$((now + 540))" # <= 10 minutes from iat

header='{"alg":"RS256","typ":"JWT"}'
payload="{\"iat\":${iat},\"exp\":${exp},\"iss\":\"${GH_APP_ID}\"}"

header_b64="$(printf '%s' "$header" | b64url)"
payload_b64="$(printf '%s' "$payload" | b64url)"
unsigned_token="${header_b64}.${payload_b64}"

signature_b64="$(
  printf '%s' "$unsigned_token" \
    | openssl dgst -binary -sha256 -sign "$GH_APP_PRIVATE_KEY_PATH" \
    | b64url
)"

GH_APP_JWT="${unsigned_token}.${signature_b64}"

# Discover installation ID if not provided
if [[ -z "${GH_INSTALLATION_ID:-}" ]]; then
  if [[ -n "${GH_REPO:-}" ]]; then
    GH_INSTALLATION_ID="$(
      curl -fsSL \
        -H "Authorization: Bearer ${GH_APP_JWT}" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/repos/${GH_ORG}/${GH_REPO}/installation" \
      | jq -r '.id'
    )"
  else
    GH_INSTALLATION_ID="$(
      curl -fsSL \
        -H "Authorization: Bearer ${GH_APP_JWT}" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/orgs/${GH_ORG}/installation" \
      | jq -r '.id'
    )"
  fi
fi

[[ "$GH_INSTALLATION_ID" != "null" && -n "$GH_INSTALLATION_ID" ]] || {
  echo "Could not determine GH_INSTALLATION_ID" >&2
  exit 1
}

# Exchange app JWT for installation access token (valid ~1 hour)
install_resp="$(
  curl -fsSL -X POST \
    -H "Authorization: Bearer ${GH_APP_JWT}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/app/installations/${GH_INSTALLATION_ID}/access_tokens"
)"

GH_INSTALLATION_TOKEN="$(printf '%s' "$install_resp" | jq -r '.token')"
GH_INSTALLATION_TOKEN_EXPIRES_AT="$(printf '%s' "$install_resp" | jq -r '.expires_at')"

[[ "$GH_INSTALLATION_TOKEN" != "null" && -n "$GH_INSTALLATION_TOKEN" ]] || {
  echo "Failed to obtain installation token" >&2
  echo "$install_resp" | jq -r '.message // empty' >&2 || true
  exit 1
}

echo "Installation token acquired; expires at: ${GH_INSTALLATION_TOKEN_EXPIRES_AT}"

# Optional: immediately fetch an org runner registration token
reg_resp="$(
  curl -fsSL -X POST \
    -H "Authorization: Bearer ${GH_INSTALLATION_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/orgs/${GH_ORG}/actions/runners/registration-token"
)"

export RUNNER_REG_TOKEN="$(printf '%s' "$reg_resp" | jq -r '.token')"
export RUNNER_REG_TOKEN_EXPIRES_AT="$(printf '%s' "$reg_resp" | jq -r '.expires_at')"

[[ "$RUNNER_REG_TOKEN" != "null" && -n "$RUNNER_REG_TOKEN" ]] || {
  echo "Failed to obtain runner registration token" >&2
  echo "$reg_resp" | jq -r '.message // empty' >&2 || true
  exit 1
}

echo "Runner registration token acquired; expires at: ${RUNNER_REG_TOKEN_EXPIRES_AT}"