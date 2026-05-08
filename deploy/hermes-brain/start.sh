#!/usr/bin/env bash
set -euo pipefail

mkdir -p "${HERMES_HOME:-/opt/autovmware-hermes-brain/hermes}" \
  /opt/autovmware-hermes-brain/state \
  /opt/autovmware-hermes-brain/logs

export HERMES_HOME="${HERMES_HOME:-/opt/autovmware-hermes-brain/hermes}"
export HERMES_PROFILE="${HERMES_PROFILE:-autovmware-brain}"
export BRAIN_API_HOST="${BRAIN_API_HOST:-0.0.0.0}"
export BRAIN_API_PORT="${BRAIN_API_PORT:-3104}"
export BRAIN_STATE_PATH="${BRAIN_STATE_PATH:-/opt/autovmware-hermes-brain/state/workers.json}"

python /opt/autovmware-hermes-brain/brain_api.py \
  >>/opt/autovmware-hermes-brain/logs/brain-api.log \
  2>>/opt/autovmware-hermes-brain/logs/brain-api.err &
api_pid=$!

cleanup() {
  kill "$api_pid" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Hermes Feishu websocket credentials come from env file. Never bake them into image.
exec python -m hermes_cli.main gateway run --replace
