#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${APP_NAME:-autovmware-hermes-brain}"
APP_DIR="${APP_DIR:-/opt/autovmware-hermes-brain}"
IMAGE_TAG="${IMAGE_TAG:-localhost/${APP_NAME}:latest}"
BRAIN_PORT="${BRAIN_PORT:-3104}"
ENV_FILE="${ENV_FILE:-${APP_DIR}/brain.env}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root on Aliyun ECS." >&2
  exit 1
fi

install_podman() {
  if command -v podman >/dev/null 2>&1; then
    podman --version
    return 0
  fi
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y podman uidmap slirp4netns fuse-overlayfs
  podman --version
}

prepare_dirs() {
  install -d -m 0750 "${APP_DIR}" "${APP_DIR}/state" "${APP_DIR}/logs" "${APP_DIR}/hermes"
  if [[ ! -f "${ENV_FILE}" ]]; then
    install -m 0600 "${REPO_DIR}/deploy/hermes-brain/env.example" "${ENV_FILE}"
    echo "Created ${ENV_FILE}; fill real Feishu/model credentials before starting." >&2
    exit 2
  fi
  chmod 0600 "${ENV_FILE}"
}

build_image() {
  podman build -t "${IMAGE_TAG}" -f "${REPO_DIR}/deploy/hermes-brain/Containerfile" "${REPO_DIR}"
}

write_unit() {
  cat >"/etc/systemd/system/${APP_NAME}.service" <<EOF
[Unit]
Description=AutoVMware Hermes Brain (Podman)
Wants=network-online.target
After=network-online.target

[Service]
Restart=always
RestartSec=5
EnvironmentFile=${ENV_FILE}
ExecStartPre=-/usr/bin/podman rm -f ${APP_NAME}
ExecStart=/usr/bin/podman run --name ${APP_NAME} --replace \\
  --env-file ${ENV_FILE} \\
  -p ${BRAIN_PORT}:${BRAIN_PORT} \\
  -v ${APP_DIR}/hermes:/opt/autovmware-hermes-brain/hermes:Z \\
  -v ${APP_DIR}/state:/opt/autovmware-hermes-brain/state:Z \\
  -v ${APP_DIR}/logs:/opt/autovmware-hermes-brain/logs:Z \\
  ${IMAGE_TAG}
ExecStop=/usr/bin/podman stop -t 30 ${APP_NAME}

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
}

case "${1:-deploy}" in
  install-podman)
    install_podman
    ;;
  build)
    install_podman
    build_image
    ;;
  deploy)
    install_podman
    prepare_dirs
    build_image
    write_unit
    systemctl enable --now "${APP_NAME}.service"
    systemctl --no-pager --full status "${APP_NAME}.service" | sed -n '1,40p'
    curl -fsS "http://127.0.0.1:${BRAIN_PORT}/health"
    echo
    ;;
  status)
    systemctl --no-pager --full status "${APP_NAME}.service" | sed -n '1,80p' || true
    podman ps --filter "name=${APP_NAME}" --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' || true
    curl -fsS "http://127.0.0.1:${BRAIN_PORT}/health" || true
    echo
    ;;
  *)
    echo "Usage: $0 [install-podman|build|deploy|status]" >&2
    exit 64
    ;;
esac
