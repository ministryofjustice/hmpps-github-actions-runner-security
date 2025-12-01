#!/usr/bin/env bash
set -euo pipefail

# Remove docker-clean config that would override Keep-Downloaded-Packages
rm -f /etc/apt/apt.conf.d/docker-clean
echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

# Remove lock files from cache mounts (Docker best practice)
rm -f /var/cache/apt/archives/lock
rm -f /var/lib/apt/lists/lock

# Required by the build or runner operation
function install_essentials() {
  apt-get install -y --no-install-recommends \
      libicu-dev \
      lsb-release \
      ca-certificates \
      locales \
      openjdk-25-jre-headless \
      curl \
      jq
}

function install_tools_apt() {
  apt_packages | xargs apt-get install -y --no-install-recommends
}

function remove_caches() {
  # Don't clean apt caches - they're persisted by BuildKit cache mounts
  # This follows Docker's recommended pattern for cache mounts:
  # https://docs.docker.com/reference/dockerfile/#example-cache-apt-packages
  
  # Clean temp directories to reduce final image size
  rm -rf /tmp/*
  rm -rf /var/tmp/*
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
install_tools_apt
install_tools

remove_caches
