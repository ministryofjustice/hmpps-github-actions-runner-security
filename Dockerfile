#checkov:skip=CKV_DOCKER_2:actions/runner does not provider a mechanism for checking the health of the service
FROM public.ecr.aws/ubuntu/ubuntu:24.04_stable

LABEL org.opencontainers.image.vendor="Ministry of Justice" \
      org.opencontainers.image.authors="HMPPS DPS" \
      org.opencontainers.image.title="Actions Runner" \
      org.opencontainers.image.description="Actions Runner image for HMPPS DPS" \
      org.opencontainers.image.url="https://github.com/ministryofjustice/hmpps-github-actions-runner"

ENV CONTAINER_USER="runner" \
    CONTAINER_UID="10000" \
    CONTAINER_GROUP="runner" \
    CONTAINER_GID="10000" \
    CONTAINER_HOME="/actions-runner" \
    DEBIAN_FRONTEND="noninteractive"

# Checked by renovate
ENV ACTIONS_RUNNER_VERSION="2.327.1"
ENV GIT_LFS_VERSION="3.7.0"

# Prepare the runner
RUN <<EOF

groupadd \
  --gid ${CONTAINER_GID} \
  --system \
  ${CONTAINER_GROUP}

useradd \
  --uid ${CONTAINER_UID} \
  --gid ${CONTAINER_GROUP} \
  --create-home \
  ${CONTAINER_USER}

mkdir --parents ${CONTAINER_HOME}

chown --recursive ${CONTAINER_USER}:${CONTAINER_GROUP} ${CONTAINER_HOME}


curl --location "https://github.com/actions/runner/releases/download/v${ACTIONS_RUNNER_VERSION}/actions-runner-linux-x64-${ACTIONS_RUNNER_VERSION}.tar.gz" \
  --output "actions-runner-linux-x64-${ACTIONS_RUNNER_VERSION}.tar.gz"

# Validate the checksum
ACTIONS_RUNNER_PKG_SHA=$(curl -s --location "https://github.com/actions/runner/releases/tag/v${ACTIONS_RUNNER_VERSION}" | grep -A10 "SHA-256 Checksums" | grep actions-runner-linux-x64-${ACTIONS_RUNNER_VERSION} | awk -F'[<> ]' '{print $4}')
echo "Release ACTIONS_RUNNER_PKG_SHA   : ${ACTIONS_RUNNER_PKG_SHA}"
echo "Downloaded ACTIONS_RUNNER_PKG_SHA: $(sha256sum -b actions-runner-linux-x64-${ACTIONS_RUNNER_VERSION}.tar.gz) | cut -d\  -f1"

echo "${ACTIONS_RUNNER_PKG_SHA}"  "actions-runner-linux-x64-${ACTIONS_RUNNER_VERSION}.tar.gz" | /usr/bin/sha256sum --check

tar --extract --gzip --file="actions-runner-linux-x64-${ACTIONS_RUNNER_VERSION}.tar.gz" --directory="${CONTAINER_HOME}"

rm --force "actions-runner-linux-x64-${ACTIONS_RUNNER_VERSION}.tar.gz"
EOF

COPY --chown=nobody:nobody --chmod=0755 src/usr/local/bin/entrypoint.sh /usr/local/bin/entrypoint.sh

USER ${CONTAINER_UID}

WORKDIR ${CONTAINER_HOME}

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
