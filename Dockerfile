# syntax=docker/dockerfile:1

ARG OPENCODE_VERSION=1.18.32
ARG STUDIO_VERSION=2.4.5

FROM node:22-bookworm-slim AS studio-builder
ARG STUDIO_VERSION
WORKDIR /build/opencode-studio

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates git \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch "v${STUDIO_VERSION}" \
      https://github.com/Microck/opencode-studio.git .

WORKDIR /build/opencode-studio/client-next
RUN npm install && npm run build

WORKDIR /build/opencode-studio/server
RUN npm install --omit=dev

FROM debian:bookworm-slim AS runtime
ARG OPENCODE_VERSION
ARG TARGETARCH

ENV HOME=/data \
    OPENCODE_CONFIG_DIR=/data/.config/opencode \
    NODE_ENV=production \
    PATH=/usr/local/bin:$PATH

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash ca-certificates curl git ripgrep tini \
    && rm -rf /var/lib/apt/lists/* \
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

# Runtime needs Node, but not npm, headers or the full Node image.
COPY --from=studio-builder /usr/local/bin/node /usr/local/bin/node

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

COPY --from=studio-builder /build/opencode-studio/server/ /opt/opencode-studio/server/
COPY --from=studio-builder /build/opencode-studio/client-next/.next/standalone/ /opt/opencode-studio/client/
COPY --from=studio-builder /build/opencode-studio/client-next/.next/static/ /opt/opencode-studio/client/.next/static/
COPY --from=studio-builder /build/opencode-studio/client-next/public/ /opt/opencode-studio/client/public/

COPY entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod 0755 /usr/local/bin/entrypoint.sh \
    && chown -R opencode:opencode /data /opt/opencode-studio

VOLUME ["/data"] 

USER opencode
WORKDIR /data/workspace
EXPOSE 4096 1080

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=5 \
  CMD curl -fsS http://127.0.0.1:4096/ || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
