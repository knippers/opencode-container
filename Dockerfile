FROM node:22-bookworm-slim

ARG OPENCODE_VERSION=2.0.7
ARG STUDIO_VERSION=2.4.5

ENV HOME=/home/opencode \
    OPENCODE_CONFIG_DIR=/home/opencode/.config/opencode \
    NODE_ENV=production \
    PATH=/home/opencode/.opencode/bin:$PATH

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git ripgrep tini \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --home-dir /home/opencode --shell /bin/bash opencode \
    && mkdir -p /home/opencode/.config/opencode \
                /home/opencode/.config/opencode-studio \
                /home/opencode/.config/opencode-profiles \
                /home/opencode/.local/share \
                /workspace \
                /opt/opencode-studio \
    && chown -R opencode:opencode /home/opencode /workspace /opt/opencode-studio

# Install the pinned OpenCode release directly from its official GitHub release.
# TARGETARCH is supplied by Docker Buildx, allowing one workflow to publish
# amd64 and arm64 images.
ARG TARGETARCH
RUN case "${TARGETARCH}" in \
      amd64) OPENCODE_ARCH="x64" ;; \
      arm64) OPENCODE_ARCH="arm64" ;; \
      *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && curl -fsSL \
      "https://github.com/anomalyco/opencode/releases/download/v${OPENCODE_VERSION}/opencode-linux-${OPENCODE_ARCH}.tar.gz" \
      -o /tmp/opencode.tar.gz \
    && tar -xzf /tmp/opencode.tar.gz -C /usr/local/bin opencode \
    && chmod 0755 /usr/local/bin/opencode \
    && rm /tmp/opencode.tar.gz \
    && opencode --version

# Build the pinned OpenCode Studio release from its upstream source.
RUN git clone --depth 1 --branch "v${STUDIO_VERSION}" \
      https://github.com/Microck/opencode-studio.git /opt/opencode-studio \
    && cd /opt/opencode-studio \
    && npm install --omit=dev \
    && chown -R opencode:opencode /opt/opencode-studio

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh \
    && chown opencode:opencode /usr/local/bin/entrypoint.sh

USER opencode
WORKDIR /workspace

EXPOSE 4096 1080

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=5 \
  CMD curl -fsS http://127.0.0.1:4096/ || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
