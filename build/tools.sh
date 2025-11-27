#!/usr/bin/env bash
set -euo pipefail

function install_vulnz() {
# install the latest version of the vulnz tool
  mkdir -p /opt/vulnz/cache
  curl -L -o /opt/vulnz/vulnz.jar https://github.com/jeremylong/open-vulnerability-cli/releases/download/v${VULNZ_VERSION}/vulnz-${VULNZ_VERSION}.jar
  chmod -R a+xr /opt/vulnz
  chmod -R a+w /opt/vulnz/cache
}

function install_tools() {
  local function_name
  # shellcheck source=/dev/null
  source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

  script_packages | while read -r package; do
    function_name="install_${package}"
    if declare -f "${function_name}" > /dev/null; then
      "${function_name}"
    else
      echo "No install script found for package: ${package}"
      exit 1
    fi
  done
}
