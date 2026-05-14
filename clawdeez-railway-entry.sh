#!/bin/bash
# Railway entrypoint for ClawDeez Hermes deployments.
#
# Two jobs, in order:
#   1. Map Railway's dynamic $PORT onto Hermes' API server port so /health resolves.
#   2. Materialize /opt/data/config.yaml from provisioning env vars BEFORE the upstream
#      entrypoint runs.
#
# Why we own config.yaml here: Hermes documents `config.yaml` as the "single source of
# truth" for `model:` / `provider:` / `base_url:` / `api_key:` (see
# https://hermes-agent.nousresearch.com/docs/integrations/providers#custom--self-hosted-llm-providers).
# Pure env-var configuration of `provider: custom` is unreliable — even after the fix
# in NousResearch/hermes-agent#15103, OPENAI_BASE_URL gets honored but OPENAI_API_KEY
# is masked when the upstream entrypoint copies its default .env.example onto a fresh
# Railway volume (.env load runs with override semantics for the custom-provider path).
# Writing config.yaml ourselves sidesteps both quirks and is forward-compatible with
# whatever the upstream entrypoint decides to copy next.
set -euo pipefail

export API_SERVER_PORT="${PORT:-8642}"
export API_SERVER_ENABLED="${API_SERVER_ENABLED:-true}"
export API_SERVER_HOST="${API_SERVER_HOST:-0.0.0.0}"

DATA_DIR="${HERMES_HOME:-/opt/data}"
mkdir -p "$DATA_DIR"

PROVIDER="${HERMES_INFERENCE_PROVIDER:-}"
MODEL="${HERMES_MODEL:-}"

if [ -n "$PROVIDER" ] && [ -n "$MODEL" ]; then
  CONFIG_PATH="$DATA_DIR/config.yaml"
  TMP_PATH="$DATA_DIR/.config.yaml.clawdeez-tmp"

  # Escape any embedded double-quote so we can wrap scalars in YAML "..." strings safely.
  # Model ids and base URLs never contain quotes in practice; Morpheus / OpenRouter keys
  # are URL-safe base64. This is belt-and-braces in case a future provider uses them.
  esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

  case "$PROVIDER" in
    openrouter)
      {
        printf 'model:\n'
        printf '  default: "%s"\n' "$(esc "$MODEL")"
        printf '  provider: openrouter\n'
      } > "$TMP_PATH"
      ;;
    custom)
      BASE_URL="${OPENAI_BASE_URL:-}"
      API_KEY="${OPENAI_API_KEY:-}"
      if [ -z "$BASE_URL" ] || [ -z "$API_KEY" ]; then
        echo "[clawdeez-entry] HERMES_INFERENCE_PROVIDER=custom requires OPENAI_BASE_URL and OPENAI_API_KEY" >&2
        exit 64
      fi
      {
        printf 'model:\n'
        printf '  default: "%s"\n' "$(esc "$MODEL")"
        printf '  provider: custom\n'
        printf '  base_url: "%s"\n' "$(esc "$BASE_URL")"
        printf '  api_key: "%s"\n' "$(esc "$API_KEY")"
      } > "$TMP_PATH"
      ;;
    *)
      echo "[clawdeez-entry] unsupported HERMES_INFERENCE_PROVIDER='$PROVIDER'" >&2
      exit 64
      ;;
  esac

  chmod 0600 "$TMP_PATH"
  # The upstream entrypoint drops to the `hermes` user before loading config; transfer
  # ownership so the read succeeds. Best-effort: skip silently if the user isn't there
  # (older Hermes images / non-Debian bases).
  chown hermes:hermes "$TMP_PATH" 2>/dev/null || true
  mv -f "$TMP_PATH" "$CONFIG_PATH"
fi

exec /usr/bin/tini -g -- /opt/hermes/docker/entrypoint.sh "$@"
