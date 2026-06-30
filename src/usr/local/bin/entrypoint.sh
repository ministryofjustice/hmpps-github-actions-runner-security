#!/usr/bin/env bash

set -euo pipefail

echo "Setting up NVD vulnerability database mirror"
echo "File location: /opt/vulnz/vulnz.jar"

# Validate the cache first - sometimes they get into a bit of a pickle
echo "Scanning /opt/vulnz/cache..."
CACHE_BAD=""
for gzfile in /opt/vulnz/cache/*.gz; do
  # Skip the glob literal if the directory is empty
  [[ -e "$gzfile" ]] || continue
  # Remove zero-byte files (gzip -t passes on them but they're useless)
  if [[ ! -s "$gzfile" ]]; then
    echo "Empty file detected - invalidating cache"
    CACHE_BAD=YES
    continue
  fi
  # Remove files that fail gzip integrity check
  if ! gzip -t "$gzfile" 2>/dev/null; then
    echo "Corrupt gzip file detected, invalidating cache"
    CACHE_BAD=YES
  fi
done


# POD_NAME is injected via the Kubernetes Downward API (e.g. "hmpps-github-actions-runner-security-0").
# Strip everything up to and including the last "-" to get the 0-based ordinal,
# then convert to a 1-based two-digit index to match secret keys NVD_API_KEY_01..04.
ordinal="${POD_NAME##*-}"
pod=$(printf '%02d' $((ordinal + 1)))
key_var="NVD_API_KEY_${pod}"
export NVD_API_KEY="${!key_var:-}"

echo "NVD API KEY (NVD_API_KEY_${pod}): ${NVD_API_KEY:0:3}...${NVD_API_KEY: -3}"

# if [ $CACHE_BAD ] ; then
#   rm /opt/vulnz/cache/*
# fi
java -Xmx4g  -XX:+UseStringDeduplication -jar /opt/vulnz/vulnz.jar cve --cache --directory /opt/vulnz/cache  --requestCount=30 --debug --delay=8000 --maxRetry=40
echo "Database mirror setup initiated - now starting the runner"

ACTIONS_RUNNER_DIRECTORY="/actions-runner"
EPHEMERAL="${EPHEMERAL:-"false"}"

# Point to the mounted private key secret
export GH_APP_PRIVATE_KEY_PATH="/var/run/secrets/github-app/private-key.pem"

if [[ ! -r "${GH_APP_PRIVATE_KEY_PATH}" ]]; then
  echo "ERROR: Private key not readable at ${GH_APP_PRIVATE_KEY_PATH}" >&2
  echo "Verify that the 'github-app' secret volume is mounted correctly." >&2
  exit 1
fi

# Get the token 
source /usr/local/bin/get_token.sh

# Append a random suffix so each startup registers a unique name.
# The StatefulSet hostname is stable across restarts, so without this a restarting
# pod can collide with its own previous registration before GitHub deregisters it.
RUNNER_NAME="$(hostname)-$(openssl rand -hex 4)"

echo "Runner parameters:"
echo "  GitHub org: ${GH_ORG}"
echo "  Runner Name: ${RUNNER_NAME}"
echo "  Runner Label: ${RUNNER_LABEL}"
echo "  Runner group: ${RUNNER_GROUP}"

# Clean up any previous runner configuration to avoid conflicts on restart.
echo "Cleaning up previous runner configuration (if any)"
rm -f "${ACTIONS_RUNNER_DIRECTORY}/.runner" \
      "${ACTIONS_RUNNER_DIRECTORY}/.credentials" \
      "${ACTIONS_RUNNER_DIRECTORY}/.credentials_rsaparams"

# get_token.sh already minted and exported RUNNER_REG_TOKEN via GitHub App JWT flow.
# Use it directly — no further API call needed.
REPO_TOKEN="${RUNNER_REG_TOKEN}"

if [[ "${EPHEMERAL}" == "true" ]]; then
  EPHEMERAL_FLAG="--ephemeral"
  trap 'echo "Shutting down runner"; exit' SIGINT SIGQUIT SIGTERM INT TERM QUIT
else
  EPHEMERAL_FLAG=""
fi

echo "Configuring runner"
bash "${ACTIONS_RUNNER_DIRECTORY}/config.sh" ${EPHEMERAL_FLAG} \
  --unattended \
  --disableupdate \
  --url "https://github.com/${GH_ORG}" \
  --token "${REPO_TOKEN}" \
  --name "${RUNNER_NAME}" \
  --labels "${RUNNER_LABEL}" \
  --runnergroup "${RUNNER_GROUP}"

echo "Setting the 'ready' flag for Kubernetes readiness probe"
touch /tmp/runner.ready

echo "Starting runner"
bash "${ACTIONS_RUNNER_DIRECTORY}/run.sh"
