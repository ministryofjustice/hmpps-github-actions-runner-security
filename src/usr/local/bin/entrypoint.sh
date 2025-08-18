#!/usr/bin/env bash

set -euo pipefail

echo "Setting up NVD vulnerability database mirror"
echo "File location: /opt/vulnz/vulnz.jar"

export pod=$(printf '%02d' ${POD_NUMBER})
export key_var="NVD_API_KEY_${pod}"
export NVD_API_KEY="${!key_var}"

echo "NVD API KEY (NVD_API_KEY_${pod}): ${NVD_API_KEY:0:3}...${NVD_API_KEY: -3}"
nohup java -Xmx2g -jar /opt/vulnz/vulnz.jar cve --cache --directory /opt/vulnz/cache &

echo "Database mirror setup initiated - now starting the runner"

ACTIONS_RUNNER_DIRECTORY="/actions-runner"
EPHEMERAL="${EPHEMERAL:-"false"}"

echo "Runner parameters:"
echo "  GitHub org: ${GH_ORG}"
echo "  Runner Name: $(hostname)"
echo "  Runner Labels: ${RUNNER_LABEL}"
echo "  Runner group: ${RUNNER_GROUP}"

echo "Obtaining registration token"
getRegistrationToken=$(
  curl \
    --silent \
    --location \
    --request "POST" \
    --header "Accept: application/vnd.github+json" \
    --header "X-GitHub-Api-Version: 2022-11-28" \
    --header "Authorization: Bearer ${GH_AUTH_TOKEN}" \
    "https://api.github.com/orgs/${GH_ORG}/actions/runners/registration-token" | jq -r '.token'
)
export getRegistrationToken

echo "Checking if registration token exists"
if [[ -z "${getRegistrationToken}" ]]; then
  echo "Failed to obtain registration token"
  exit 1
else
  echo "Registration token obtained successfully"
  REPO_TOKEN="${getRegistrationToken}"
fi

if [[ "${EPHEMERAL}" == "true" ]]; then
  EPHEMERAL_FLAG="--ephemeral"
  trap 'echo "Shutting down runner"; exit' SIGINT SIGQUIT SIGTERM INT TERM QUIT
else
  EPHEMERAL_FLAG=""
fi

echo "Checking the runner"
bash "${ACTIONS_RUNNER_DIRECTORY}/config.sh" --check --url "https://github.com/${GH_ORG}" --pat ${GH_AUTH_TOKEN}

echo "Configuring runner"
bash "${ACTIONS_RUNNER_DIRECTORY}/config.sh" ${EPHEMERAL_FLAG} \
  --unattended \
  --disableupdate \
  --url "https://github.com/${GH_ORG}" \
  --token "${REPO_TOKEN}" \
  --name "$(hostname)" \
  --labels "${RUNNER_LABEL}" \
  --runnergroup "${RUNNER_GROUP}"

echo "Setting the 'ready' flag for Kubernetes liveness probe"
touch /tmp/runner.ready

echo "Starting runner"
bash "${ACTIONS_RUNNER_DIRECTORY}/run.sh"
