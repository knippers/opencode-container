#!/usr/bin/env bash
set -euo pipefail

: "${HOME:?HOME must be set}"
: "${OPENCODE_CONFIG_DIR:=${HOME}/.config/opencode}"

STUDIO_SERVER_DIR="/opt/opencode-studio/server"
STUDIO_CLIENT_DIR="/opt/opencode-studio/client"

mkdir -p \
  "${OPENCODE_CONFIG_DIR}" \
  "${HOME}/.config/opencode-studio" \
  "${HOME}/.config/opencode-profiles" \
  "${HOME}/.local/share" \
  "${HOME}/workspace"

if [[ ! -f "${OPENCODE_CONFIG_DIR}/opencode.json" ]]; then
  cat > "${OPENCODE_CONFIG_DIR}/opencode.json" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json"
}
EOF
fi

declare -A PIDS=()

# Starts a command in the given working directory as a background job,
# records its PID under $name, and logs the start for container visibility.
start_service() {
  local name="$1" dir="$2"
  shift 2
  ( cd "${dir}" && exec "$@" ) &
  PIDS["${name}"]=$!
  echo "entrypoint: started ${name} (pid ${PIDS[${name}]})" >&2
}

cleanup() {
  local name
  for name in "${!PIDS[@]}"; do
    kill "${PIDS[${name}]}" 2>/dev/null || true
  done
  wait 2>/dev/null || true
}
trap cleanup TERM INT EXIT

start_service opencode . \
  opencode serve --hostname 0.0.0.0 --port 4096

start_service studio-server "${STUDIO_SERVER_DIR}" \
  node index.js

start_service studio-client "${STUDIO_CLIENT_DIR}" \
  env PORT=1080 HOSTNAME=0.0.0.0 node server.js

set +e
wait -n "${PIDS[@]}"
exit_code=$?
set -e

echo "entrypoint: a service exited (code ${exit_code}); shutting down" >&2
exit "${exit_code}"