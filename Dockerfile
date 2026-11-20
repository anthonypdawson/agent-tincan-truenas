# syntax=docker/dockerfile:1
# Agent Tincan as a TrueNAS SCALE app.
#
# There is no Dockerfile or image upstream (mvanhorn/agent-tincan ships
# release binaries only), so this image is built from the upstream
# release binary for the target architecture and verified against the
# release's checksums.txt.
#
# Multi-arch: linux/amd64 and linux/arm64. Build with buildx, for example:
#   docker buildx build --platform linux/amd64,linux/arm64 \
#     --build-arg TINCAN_VERSION=v0.28.2 -t ghcr.io/anthonypdawson/agent-tincan:v0.28.2 .
#
# The image entrypoint is the tincan binary. The mode (relay vs agent) is
# chosen by the command at run time, not by a different image. The
# default command runs the relay.

ARG TINCAN_VERSION=v0.28.2

FROM debian:bookworm-slim AS downloader
ARG TINCAN_VERSION
ARG TARGETARCH
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /dl
# Upstream release assets are plain binaries (not tarballs):
# tincan_linux_amd64, tincan_linux_arm64, plus checksums.txt in the
# standard "<sha256>  <filename>" format.
RUN curl -fsSL -o checksums.txt \
      "https://github.com/mvanhorn/agent-tincan/releases/download/${TINCAN_VERSION}/checksums.txt" \
    && curl -fsSL -o "tincan_linux_${TARGETARCH}" \
      "https://github.com/mvanhorn/agent-tincan/releases/download/${TINCAN_VERSION}/tincan_linux_${TARGETARCH}" \
    && grep "tincan_linux_${TARGETARCH}" checksums.txt > check.sha \
    && sha256sum -c check.sha \
    && mv "tincan_linux_${TARGETARCH}" tincan \
    && chmod +x tincan

FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=downloader /dl/tincan /usr/local/bin/tincan
# The relay's state lives in /state: relay.db, relay.key, invite-pepper,
# wake.json, approval.json, the attachments directory, and the Tailscale
# node state. Mount a TrueNAS dataset here so it survives app updates
# and restarts. Never run the relay with container-local state.
RUN mkdir -p /state
VOLUME ["/state"]
ENTRYPOINT ["tincan"]
# Default: run the relay. --dist and --release-url are what make
# `tincan relay-upgrade --from-github` work, so upgrades do not need a
# new image. --admin is set by the compose file / catalog wizard; the
# relay host itself is always an admin with no flags.
CMD ["relay", "--state-dir", "/state", "--dist", "/state/dist", "--release-url", "https://github.com/mvanhorn/agent-tincan/releases/download"]
