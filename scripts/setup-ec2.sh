#!/usr/bin/env bash
# Install host prerequisites for this project on a fresh Ubuntu machine (e.g. EC2).
# Does not start the app — only installs Docker, Compose, and related tools.
#
# Usage (from the repo root):
#   chmod +x scripts/setup-ec2.sh
#   ./scripts/setup-ec2.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

log() { echo "==> $*"; }
fail() { echo "ERROR: $*" >&2; exit 1; }

if [[ "$(id -u)" -eq 0 ]]; then
  fail "Run this script as a normal user (e.g. ubuntu), not as root. It will use sudo when needed."
fi

if ! command -v sudo >/dev/null 2>&1; then
  fail "sudo is required."
fi

if [[ ! -f /etc/os-release ]]; then
  fail "Unsupported OS: /etc/os-release not found."
fi
# shellcheck disable=SC1091
. /etc/os-release
if [[ "${ID:-}" != "ubuntu" ]]; then
  fail "This script supports Ubuntu only (detected: ${ID:-unknown})."
fi

log "Installing base packages"
sudo apt-get update -y
sudo apt-get install -y ca-certificates curl git

if ! command -v docker >/dev/null 2>&1; then
  log "Installing Docker Engine and Compose plugin"
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    ${VERSION_CODENAME} stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  sudo apt-get update -y
  sudo apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin
else
  log "Docker already installed: $(docker --version)"
fi

log "Starting Docker service"
sudo systemctl enable docker
sudo systemctl start docker

TARGET_USER="$(id -un)"
if ! id -nG "$TARGET_USER" | tr ' ' '\n' | grep -qx docker; then
  log "Adding user '${TARGET_USER}' to the docker group"
  sudo usermod -aG docker "$TARGET_USER"
else
  log "User '${TARGET_USER}' is already in the docker group"
fi

if [[ ! -f .env && -f .env.example ]]; then
  log "Creating .env from .env.example (edit before first start if needed)"
  cp .env.example .env
fi

echo
log "Prerequisites installed"
echo "    docker:         $(docker --version 2>/dev/null || echo 'installed — re-login to use without sudo')"
echo "    docker compose: $(docker compose version 2>/dev/null || echo 'installed — re-login to use without sudo')"
echo
echo "    Next steps:"
echo "      1. Log out and SSH back in (or run: newgrp docker)"
echo "      2. Edit .env if you want custom credentials:  nano .env"
echo "      3. Start the app:  docker compose up --build -d"
echo "         Or after CI/CD is configured, push to main / run:  ./scripts/deploy.sh"
