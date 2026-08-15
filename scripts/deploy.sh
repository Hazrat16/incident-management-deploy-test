#!/usr/bin/env bash
# Run on the EC2 host from the app directory after git has been updated.
set -euo pipefail

# Non-interactive SSH sessions often have a minimal PATH.
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

echo "==> Working directory: $(pwd)"

if [[ ! -f .env ]]; then
  if [[ ! -f .env.example ]]; then
    echo "Missing .env and .env.example — cannot configure the stack."
    exit 1
  fi
  echo "==> No .env found — creating from .env.example"
  echo "    Edit .env on the server later if you need different credentials."
  cp .env.example .env
fi

# Load DOCKERHUB_USERNAME / IMAGE_TAG for compose image names.
# IMAGE_TAG already set in the environment (e.g. by CI) wins over .env
PRESET_IMAGE_TAG="${IMAGE_TAG:-}"
set -a
# shellcheck disable=SC1091
source .env
set +a
IMAGE_TAG="${PRESET_IMAGE_TAG:-${IMAGE_TAG:-latest}}"

if ! command -v docker >/dev/null 2>&1; then
  echo "==> Docker not found — running scripts/setup-ec2.sh to install prerequisites"
  chmod +x scripts/setup-ec2.sh
  ./scripts/setup-ec2.sh
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is still not available after setup. Install it manually, then re-run deploy."
  exit 1
fi

run_docker() {
  if docker info >/dev/null 2>&1; then
    "$@"
  elif command -v sg >/dev/null 2>&1 && id -nG 2>/dev/null | tr ' ' '\n' | grep -qx docker; then
    local quoted
    printf -v quoted '%q ' "$@"
    sg docker -c "$quoted"
  else
    # GitHub Actions SSH sessions often lack the docker group even after usermod.
    sudo "$@"
  fi
}

if [[ -n "${DOCKERHUB_USERNAME:-}" && "${DOCKERHUB_USERNAME}" != "local" ]]; then
  echo "==> Pulling images from Docker Hub (user: ${DOCKERHUB_USERNAME}, tag: ${IMAGE_TAG:-latest})"
  run_docker docker compose pull backend frontend
  echo "==> Starting stack from pulled images"
  run_docker docker compose up -d --no-build
else
  echo "==> DOCKERHUB_USERNAME not set — building images on this host"
  run_docker docker compose up --build -d
fi

echo "==> Waiting for containers to report healthy"
deadline=$((SECONDS + 180))
while (( SECONDS < deadline )); do
  mapfile -t statuses < <(run_docker docker compose ps --format '{{.Health}}' 2>/dev/null || true)
  if ((${#statuses[@]} == 0)); then
    sleep 5
    continue
  fi

  all_healthy=true
  for status in "${statuses[@]}"; do
    # Services without a healthcheck report empty health — treat as ok if running.
    if [[ -n "$status" && "$status" != "healthy" ]]; then
      all_healthy=false
      break
    fi
  done

  if [[ "$all_healthy" == true ]]; then
    break
  fi
  sleep 5
done

echo "==> Service status"
run_docker docker compose ps

echo "==> Health checks"
curl -fsS "http://127.0.0.1:5000/health"
echo
curl -fsS -o /dev/null -w "frontend HTTP %{http_code}\n" "http://127.0.0.1:3000/"

echo "==> Deploy finished"
