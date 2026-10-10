#!/usr/bin/env bash
set -euo pipefail

: "${HOME:?HOME must be set}"
: "${OPENCODE_CONFIG_DIR:=${HOME}/.config/opencode}"

# The container starts as root so it can fix ownership of bind-mounted host
# folders (for example, root-owned Synology shares). It then re-runs this
# script as the opencode user, so the services never run as root.
if [[ "$(id -u)" -eq 0 ]]; then
  RUN_UID="$(id -u opencode)"
  RUN_GID="$(id -g opencode)"
  mkdir -p "${HOME}"
  # Some hosts (Docker Desktop file sharing, NFS with root squash, or DSM ACLs)
  # refuse chown on bind mounts. Warn and continue; the writability check below
  # reports a clear error if the opencode user really cannot write there.
  if ! chown -R "${RUN_UID}:${RUN_GID}" "${HOME}" 2>/dev/null; then
    echo "entrypoint: warning: could not change ownership of ${HOME}; checking write access as opencode" >&2
  fi
  # Probe with a real write rather than `test -w`: some bind-mount drivers
  # (for example Docker Desktop file sharing on macOS) report writable but refuse writes.
  if ! setpriv --reuid="${RUN_UID}" --regid="${RUN_GID}" --init-groups -- \
      sh -c 'probe="${HOME}/.write-probe.$$" && touch "$probe" && rm -f "$probe"' 2>/dev/null; then
    echo "entrypoint: error: user opencode (uid ${RUN_UID}) cannot write to ${HOME}." >&2
    echo "entrypoint: fix the host folder owner to ${RUN_UID}:${RUN_GID} (or grant write access in DSM), then restart." >&2
    exit 1
  fi
  exec setpriv --reuid="${RUN_UID}" --regid="${RUN_GID}" --init-groups -- "$0" "$@"
fi

STUDIO_SERVER_DIR="/opt/opencode-studio/server"
STUDIO_CLIENT_DIR="/opt/opencode-studio/client"

mkdir -p \
  "${OPENCODE_CONFIG_DIR}" \
  "${HOME}/.config/opencode-studio" \
  "${HOME}/.config/opencode-profiles" \
  "${HOME}/.local/share" \
  "${HOME}/workspace"

cd "${HOME}/workspace"

if [[ ! -f "${OPENCODE_CONFIG_DIR}/opencode.json" ]]; then
  cat > "${OPENCODE_CONFIG_DIR}/opencode.json" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json"
}
EOF
fi

declare -A PIDS=()

# Runs one service and restarts it whenever it exits, so a service that stops
# on its own (for example after an idle timeout) does not stop the container.
# Each exit is logged with the service name and exit code.
supervise() {
  local name="$1" dir="$2" child="" code=0
  shift 2
  trap '[[ -n "${child}" ]] && kill "${child}" 2>/dev/null; exit 0' TERM INT
  while true; do
    ( cd "${dir}" && exec "$@" ) &
    child=$!
    code=0
    wait "${child}" || code=$?
    echo "entrypoint: ${name} exited (code ${code}); restarting in 5s" >&2
    sleep 5
  done
}

# Starts a supervisor for one service in the background and records its PID.
start_service() {
  local name="$1" dir="$2"
  shift 2
  supervise "${name}" "${dir}" "$@" &
  PIDS["${name}"]=$!
  echo "entrypoint: started ${name} (supervisor pid ${PIDS[${name}]})" >&2
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

# Supervisors never exit on their own; this blocks until a signal stops the container.
wait