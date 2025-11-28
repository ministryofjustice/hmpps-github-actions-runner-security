#checkov:skip=CKV_DOCKER_2:actions/runner does not provider a mechanism for checking the health of the service
FROM ubuntu:noble

LABEL org.opencontainers.image.vendor="Ministry of Justice" \
      org.opencontainers.image.authors="HMPPS DPS" \
      org.opencontainers.image.title="Security Actions Runner" \
      org.opencontainers.image.description="Security Actions Runner image for HMPPS DPS" \
      org.opencontainers.image.url="https://github.com/ministryofjustice/hmpps-github-actions-runner-security"

ENV CONTAINER_USER="runner" \
    CONTAINER_UID="10000" \
    CONTAINER_GROUP="runner" \
    CONTAINER_GID="10000" \
    CONTAINER_HOME="/actions-runner" \
    DEBIAN_FRONTEND="noninteractive" \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    DUMB_INIT_VERSION="1.2.2" 

# Checked by renovate
ENV ACTIONS_RUNNER_VERSION="2.330.0" \
    GIT_LFS_VERSION="3.7.1" \
    VULNZ_VERSION="9.0.2"

SHELL ["/bin/bash", "-e", "-u", "-o", "pipefail", "-c"]

COPY --chmod=700 build/ /tmp/build/

# Install base tools and configure sources (cacheable layer)
# Cache package lists and downloaded .deb files to avoid re-downloading on rebuilds
# Pattern from: https://docs.docker.com/reference/dockerfile/#example-cache-apt-packages
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    /tmp/build/install_base.sh

# Create user and directories (stable layer)
RUN groupadd \
      --gid ${CONTAINER_GID} \
      --system \
      ${CONTAINER_GROUP} && \
    useradd \
      --uid ${CONTAINER_UID} \
      --gid ${CONTAINER_GROUP} \
      --create-home \
      ${CONTAINER_USER} && \
    mkdir --parents ${CONTAINER_HOME} && \
    chown --recursive ${CONTAINER_USER}:${CONTAINER_GROUP} ${CONTAINER_HOME}

# Download and install GitHub Actions runner (changes frequently with ACTIONS_RUNNER_VERSION)
RUN curl --location "https://github.com/actions/runner/releases/download/v${ACTIONS_RUNNER_VERSION}/actions-runner-linux-x64-${ACTIONS_RUNNER_VERSION}.tar.gz" \
      --output "actions-runner-linux-x64-${ACTIONS_RUNNER_VERSION}.tar.gz" && \
    ACTIONS_RUNNER_PKG_SHA=$(curl -s --location "https://github.com/actions/runner/releases/tag/v${ACTIONS_RUNNER_VERSION}" | grep -A10 "SHA-256 Checksums" | grep actions-runner-linux-x64-${ACTIONS_RUNNER_VERSION} | awk -F'[<> ]' '{print $4}') && \
    echo "Release ACTIONS_RUNNER_PKG_SHA   : ${ACTIONS_RUNNER_PKG_SHA}" && \
    echo "Downloaded ACTIONS_RUNNER_PKG_SHA: $(sha256sum -b actions-runner-linux-x64-${ACTIONS_RUNNER_VERSION}.tar.gz | cut -d\  -f1)" && \
    echo "${ACTIONS_RUNNER_PKG_SHA}  actions-runner-linux-x64-${ACTIONS_RUNNER_VERSION}.tar.gz" | /usr/bin/sha256sum --check && \
    tar --extract --gzip --file="actions-runner-linux-x64-${ACTIONS_RUNNER_VERSION}.tar.gz" --directory="${CONTAINER_HOME}" && \
    rm --force "actions-runner-linux-x64-${ACTIONS_RUNNER_VERSION}.tar.gz"

COPY --chown=nobody:nobody --chmod=0755 src/usr/local/bin/entrypoint.sh /usr/local/bin/entrypoint.sh

USER ${CONTAINER_UID}

WORKDIR ${CONTAINER_HOME}

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]