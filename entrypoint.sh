#!/usr/bin/env bash
set -euo pipefail

mkdir -p \
  "${HOME}/.config/opencode" \
  "${HOME}/.config/opencode-studio" \
  "${HOME}/.config/opencode-profiles" \
  "${HOME}/.local/share" \
  "${HOME}/workspace

if [[ ! -f "${OPENCODE_CONFIG_DIR}/opencode.json" ]]; then
  cat > "${OPENCODE_CONFIG_DIR}/opencode.json" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json"
}
EOF
fi

cleanup() {
  kill "${OPENCODE_PID:-}" "${STUDIO_SERVER_PID:-}" "${STUDIO_CLIENT_PID:-}" 2>/dev/null || true
  wait || true
}
trap cleanup TERM INT EXIT

opencode serve --hostname 0.0.0.0 --port 4096 &
OPENCODE_PID=$!

cd /opt/opencode-studio/server
node index.js &
STUDIO_SERVER_PID=$!

cd /opt/opencode-studio/client
PORT=1080 HOSTNAME=0.0.0.0 node server.js &
STUDIO_CLIENT_PID=$!

wait -n "${OPENCODE_PID}" "${STUDIO_SERVER_PID}" "${STUDIO_CLIENT_PID}"
exit $?
