#!/usr/bin/env bash
set -euo pipefail

mkdir -p \
  "${HOME}/.config/opencode" \
  "${HOME}/.config/opencode-studio" \
  "${HOME}/.config/opencode-profiles" \
  "${HOME}/.local/share" \
  /workspace

# Studio expects an OpenCode config to exist. Keep it intentionally minimal;
# all real configuration is expected to be managed through Studio.
if [[ ! -f "${OPENCODE_CONFIG_DIR}/opencode.json" ]]; then
  cat > "${OPENCODE_CONFIG_DIR}/opencode.json" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json"
}
EOF
fi

# Start OpenCode's HTTP server.
opencode serve \
  --hostname 0.0.0.0 \
  --port 4096 &
OPENCODE_PID=$!

cleanup() {
  kill "${OPENCODE_PID}" "${STUDIO_PID:-}" 2>/dev/null || true
  wait || true
}
trap cleanup TERM INT EXIT

# Studio's package contains the frontend and backend. Start the fully local
# mode from the upstream package. The frontend listens on 1080 by default.
cd /opt/opencode-studio
npm run start &
STUDIO_PID=$!

wait -n "${OPENCODE_PID}" "${STUDIO_PID}"
exit $?
