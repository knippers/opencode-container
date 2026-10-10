# syntax=docker/dockerfile:1

ARG OPENCODE_VERSION=1.18.32
# Pinned commit of https://github.com/knippers/opencode-studio (fork of Microck/opencode-studio).
ARG STUDIO_REF=ceadd87b306e3e61b6aa5c83db3868f63db2aceb

# Builds the OpenCode Studio client and server.
FROM node:24-bookworm-slim AS studio-builder
ARG STUDIO_REF
WORKDIR /build

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates git \
    && rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/knippers/opencode-studio.git opencode-studio \
    && cd opencode-studio \
    && git checkout "${STUDIO_REF}"

# No source patches. The client proxies /api to the backend on 127.0.0.1:1920
# (rewrites in client-next/next.config.ts), so the browser only calls same-origin /api.
WORKDIR /build/opencode-studio/client-next
RUN npm install && npm run build \
    && rm -rf /root/.npm

# --ignore-scripts skips the postinstall hook, which only registers the opencodestudio:// protocol (Windows/macOS).
WORKDIR /build/opencode-studio/server
RUN npm install --omit=dev --ignore-scripts \
    && rm -rf /root/.npm

# Downloads the OpenCode binary so curl is not needed in the runtime image.
FROM debian:bookworm-slim AS opencode-fetch
ARG OPENCODE_VERSION
ARG TARGETARCH

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

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
    && /usr/local/bin/opencode --version

FROM debian:bookworm-slim AS runtime
ARG TARGETARCH

ENV HOME=/data \
    OPENCODE_CONFIG_DIR=/data/.config/opencode \
    NODE_ENV=production \
    PATH=/usr/local/bin:$PATH

# Only the Node binary is copied from the builder; npm and headers are not shipped.
# The runtime is Debian's slim base, so Node's shared libraries come from the same base.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash ca-certificates git ripgrep tini \
    && rm -rf /var/lib/apt/lists/* \
    && find /usr/share/doc /usr/share/man /usr/share/info /var/cache -mindepth 1 -delete \
    && find /usr/share/locale -mindepth 1 -maxdepth 1 ! -name 'en*' -exec rm -rf {} + \
    && groupadd --gid 1000 opencode \
    && useradd --uid 1000 --gid 1000 --create-home --home-dir /home/opencode --shell /bin/bash opencode \
    && mkdir -p \
        /data/.config/opencode \
        /data/.config/opencode-studio \
        /data/.config/opencode-profiles \
        /data/.local/share \
        /opt/opencode-studio/server \
        /opt/opencode-studio/client \
        /data/workspace

COPY --from=studio-builder /usr/local/bin/node /usr/local/bin/node
COPY --from=opencode-fetch /usr/local/bin/opencode /usr/local/bin/opencode

COPY --from=studio-builder /build/opencode-studio/server/ /opt/opencode-studio/server/
COPY --from=studio-builder /build/opencode-studio/client-next/.next/standalone/ /opt/opencode-studio/client/
COPY --from=studio-builder /build/opencode-studio/client-next/.next/static/ /opt/opencode-studio/client/.next/static/
COPY --from=studio-builder /build/opencode-studio/client-next/public/ /opt/opencode-studio/client/public/

COPY entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod 0755 /usr/local/bin/entrypoint.sh \
    && chown -R opencode:opencode /data /opt/opencode-studio

VOLUME ["/data"]

# Starts as root; entrypoint.sh fixes ownership, then drops to the opencode user.
# No WORKDIR here: Docker would create it before the entrypoint runs, and that
# fails on root-owned bind mounts.
EXPOSE 4096 1080

# Uses Node's built-in fetch, so the runtime image does not need curl.
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=5 \
  CMD node -e "fetch('http://127.0.0.1:4096/').then(r => process.exit(r.ok ? 0 : 1), () => process.exit(1))"

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
