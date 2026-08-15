#!/usr/bin/env bash
# Run on the EC2 host from the app directory after git has been updated.
set -euo pipefail

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

echo "==> Building and starting stack"
docker compose up --build -d

echo "==> Waiting for containers to report healthy"
deadline=$((SECONDS + 180))
while (( SECONDS < deadline )); do
  mapfile -t statuses < <(docker compose ps --format '{{.Health}}' 2>/dev/null || true)
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
docker compose ps

echo "==> Health checks"
curl -fsS "http://127.0.0.1:5000/health"
echo
curl -fsS -o /dev/null -w "frontend HTTP %{http_code}\n" "http://127.0.0.1:3000/"

echo "==> Deploy finished"
