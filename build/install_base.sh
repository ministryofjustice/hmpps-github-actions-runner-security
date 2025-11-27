#!/usr/bin/env bash
set -euo pipefail

# Required by the build or runner operation
function install_essentials() {
  apt-get install -y --no-install-recommends \
      lsb-release \
      curl \
      jq
}

function install_tools_apt() {
  apt_packages | xargs apt-get install -y --no-install-recommends
}

function remove_caches() {
  rm -rf /var/lib/apt/lists/*
  rm -rf /tmp/*
}

function setup_sudoers() {
  sed -e 's/Defaults.*env_reset/Defaults env_keep = "HTTP_PROXY HTTPS_PROXY NO_PROXY FTP_PROXY http_proxy https_proxy no_proxy ftp_proxy"/' -i /etc/sudoers
  echo '%sudo ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers
}

echo en_US.UTF-8 UTF-8 >> /etc/locale.gen

scripts_dir=$(dirname "$0")
# shellcheck source=/dev/null
source "$scripts_dir/tools.sh"
# shellcheck source=/dev/null
source "$scripts_dir/config.sh"

apt-get update
install_essentials

apt-get update
install_tools

remove_sources
remove_caches
