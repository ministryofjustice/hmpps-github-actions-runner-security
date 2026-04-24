#!/usr/bin/env bash

set -euo pipefail

echo "Setting up NVD vulnerability database mirror"
echo "File location: /opt/vulnz/vulnz.jar"

# Validate the cache first - sometimes they get into a bit of a pickle
echo "Scanning /opt/vulnz/cache..."
# Purge stale files (older than 7 days) before checking integrity
find /opt/vulnz/cache -name "*.gz" -mtime +7 -print -delete
for gzfile in /opt/vulnz/cache/*.gz; do
  # Skip the glob literal if the directory is empty
  [[ -e "$gzfile" ]] || continue
  # Remove zero-byte files (gzip -t passes on them but they're useless)
  if [[ ! -s "$gzfile" ]]; then
    echo "Empty file detected, removing: $gzfile"
    rm -f "$gzfile"
    continue
  fi
  # Remove files that fail gzip integrity check
  if ! gzip -t "$gzfile" 2>/dev/null; then
    echo "Corrupt gzip file detected, removing: $gzfile"
    rm -f "$gzfile"
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
nohup java -Xmx2g -jar /opt/vulnz/vulnz.jar cve --cache --directory /opt/vulnz/cache &

echo "Database mirror setup initiated - now starting the runner"

ACTIONS_RUNNER_DIRECTORY="/actions-runner"
EPHEMERAL="${EPHEMERAL:-"false"}"

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

# ---------------------------------------------------------------------------
# Obtain a registration token with retry logic.
# GitHub App installation tokens expire after ~1 hour. If the pod restarts
# long after deploy, the GH_AUTH_TOKEN will be stale and this will fail
# permanently. Retries handle transient API/network errors only.
# ---------------------------------------------------------------------------
MAX_RETRIES=5
RETRY_DELAY=10
REPO_TOKEN=""

echo "Obtaining registration token"
for attempt in $(seq 1 "${MAX_RETRIES}"); do
  response=$(
    curl \
      --silent \
      --location \
      --request "POST" \
      --header "Accept: application/vnd.github+json" \
      --header "X-GitHub-Api-Version: 2022-11-28" \
      --header "Authorization: Bearer ${GH_AUTH_TOKEN}" \
      "https://api.github.com/orgs/${GH_ORG}/actions/runners/registration-token"
  ) || true

  token=$(echo "${response}" | jq -r '.token // empty')

  if [[ -n "${token}" ]]; then
    echo "Registration token obtained successfully (attempt ${attempt}/${MAX_RETRIES})"
    REPO_TOKEN="${token}"
    break
  fi

  error_msg=$(echo "${response}" | jq -r '.message // "unknown error"')
  echo "Failed to obtain registration token (attempt ${attempt}/${MAX_RETRIES}): ${error_msg}"

  if [[ "${attempt}" -lt "${MAX_RETRIES}" ]]; then
    sleep_time=$((RETRY_DELAY * attempt))
    echo "Retrying in ${sleep_time}s..."
    sleep "${sleep_time}"
  fi
done

if [[ -z "${REPO_TOKEN}" ]]; then
  echo "ERROR: Failed to obtain registration token after ${MAX_RETRIES} attempts."
  echo "The GH_AUTH_TOKEN is likely expired. This pod will remain alive but NOT ready"
  echo "until a new deployment provides a fresh token."
  echo "Entering idle loop — waiting for pod replacement via helm upgrade..."

  # Don't exit — that causes CrashLoopBackOff which blocks future helm upgrades.
  # The readiness probe (/tmp/runner.ready) will never be satisfied, so Kubernetes
  # won't route work to this pod. When the next helm upgrade runs, the StatefulSet
  # controller will terminate this pod and start a fresh one with a new token.
  trap 'echo "Received termination signal during idle wait — exiting"; exit 0' SIGINT SIGQUIT SIGTERM INT TERM QUIT
  while true; do
    sleep 300
  done
fi

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
