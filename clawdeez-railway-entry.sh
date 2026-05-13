#!/bin/bash
# Railway injects PORT; Hermes API server defaults to 8642. Map PORT so health checks hit /health.
set -euo pipefail
export API_SERVER_PORT="${PORT:-8642}"
export API_SERVER_ENABLED="${API_SERVER_ENABLED:-true}"
export API_SERVER_HOST="${API_SERVER_HOST:-0.0.0.0}"
exec /usr/bin/tini -g -- /opt/hermes/docker/entrypoint.sh "$@"
