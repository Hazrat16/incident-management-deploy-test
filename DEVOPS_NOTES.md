# DevOps Notes

## Image and base-image choices

- **Backend:** `node:20-alpine` — small Node LTS image, enough to run Express with production dependencies only (`npm install --omit=dev`). The process runs as the non-root `node` user.
- **Frontend build stage:** `node:20-alpine` — compiles the Vite/React app into static files under `dist/`.
- **Frontend runtime:** `nginx:1.27-alpine` — serves those static assets and reverse-proxies `/api` to the backend. Build tools and `node_modules` are not present in the final image (multi-stage build).
- **Database:** official `postgres:16-alpine` — no custom database image; configuration comes from environment variables.

## Frontend API proxying

The browser only talks to the frontend (host port `3000` → container port `80`). The React app uses relative URLs such as `/api/incidents`.

Nginx in the frontend container handles `/api/` with `proxy_pass http://backend:5000/api/` (see `frontend/nginx.conf`). That hostname resolves via Compose DNS on the shared network, so the browser never needs a hardcoded backend host.

## Service discovery

Compose provides DNS names matching service names:

| Caller   | Target hostname | Purpose                          |
| -------- | --------------- | -------------------------------- |
| Frontend | `backend`       | HTTP API via nginx proxy         |
| Backend  | `database`      | PostgreSQL (`DB_HOST=database`)  |

Cross-container traffic never uses `localhost` or fixed container IPs. PostgreSQL is not published to the host; only the frontend (and optionally the backend on `5000` for direct API checks) is exposed.

## Startup readiness

`depends_on` with `condition: service_healthy` is used instead of start-order alone:

1. **database** — healthy when `pg_isready` succeeds
2. **backend** — starts after the database is healthy; healthy when `GET /health` returns success (which also verifies DB connectivity). The app itself retries DB connections on boot.
3. **frontend** — starts after the backend is healthy; healthy when nginx responds on port 80

All services use `restart: unless-stopped`.

## PostgreSQL persistence

A named volume `postgres_data` is mounted at `/var/lib/postgresql/data`.

- `docker compose down` stops containers but keeps the volume — incident data survives a restart.
- `docker compose down -v` removes the volume and deletes database data intentionally.

## Secrets and configuration

Local credentials come from `.env` (copied from `.env.example`). Compose injects them into the database and backend services. Nothing sensitive is baked into Dockerfiles or image layers.

In a real production environment, secrets would typically come from a secrets manager or orchestrator secret store (for example Kubernetes Secrets, AWS Secrets Manager, or Docker Swarm secrets), rotated regularly, and never committed to git. Images would still receive only runtime references or mounted secret files, not plaintext passwords in build args.

## Security improvements implemented

- Backend runs as non-root (`USER node`)
- Frontend production image contains only nginx + static assets
- Database port is private to the Compose network
- `.dockerignore` files keep `node_modules`, `.env`, and other host clutter out of the build context
- Production dependency install for the backend (`--omit=dev`)

## Limitations and future improvements

- No TLS termination in this local lab (suitable for training, not public production)
- No resource limits or Compose profiles yet (optional: Adminer under a profile, CPU/memory limits)
- No CI pipeline or image vulnerability scanning yet (optional: GitHub Actions + Trivy)
- No lockfiles in the repo, so `npm install` is used instead of `npm ci`; adding lockfiles would improve build reproducibility

## Deploy to AWS EC2 (new machine checklist)

This section is enough to take a fresh Ubuntu EC2 instance from zero to a running app.

### 1. Launch the instance (AWS console)

- AMI: Ubuntu 22.04 or 24.04 LTS
- Instance size: `t3.small` (or larger)
- Security group inbound rules:
  - TCP `22` from your IP (SSH)
  - TCP `3000` from `0.0.0.0/0` (or restrict to your IP while learning)
- Optional: Elastic IP for a stable public address

Do **not** open PostgreSQL (`5432`) to the internet. Backend port `5000` is optional and better left closed publicly; the UI reaches the API through nginx on port `3000`.

### 2. SSH into the instance

```bash
ssh -i your-key.pem ubuntu@YOUR_EC2_PUBLIC_IP
```

### 3. Install Docker Engine and Compose plugin

```bash
sudo apt update
sudo apt install -y ca-certificates curl git
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

sudo usermod -aG docker ubuntu
```

Log out and SSH back in (or run `newgrp docker`) so the group membership applies.

```bash
newgrp docker
docker --version
docker compose version
```

### 4. Start the Docker daemon (if needed)

If you see:

```text
Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?
```

run:

```bash
sudo systemctl start docker
sudo systemctl enable docker
sudo systemctl status docker --no-pager
docker ps
```

Quick workaround while debugging permissions:

```bash
sudo docker compose up --build -d
```

Prefer fixing the service + `docker` group so you do not need `sudo` every time.

If `systemctl start docker` fails:

```bash
sudo journalctl -u docker --no-pager -n 50
```

### 5. Get the project onto the server

**Option A — clone from Git:**

```bash
git clone https://github.com/YOUR_USER/YOUR_REPO.git
cd YOUR_REPO
```

**Option B — copy from your laptop:**

```bash
# on your laptop
scp -i your-key.pem -r /path/to/incident-management ubuntu@YOUR_EC2_PUBLIC_IP:~/
```

Then on the EC2 instance:

```bash
cd ~/incident-management
```

### 6. Configure environment

```bash
cp .env.example .env
nano .env
```

Use a strong password on EC2. Example:

```env
POSTGRES_DB=incidentdb
POSTGRES_USER=incident_user
POSTGRES_PASSWORD=use_a_long_random_password_here
BACKEND_PORT=5000
FRONTEND_PORT=3000
```

Do not commit `.env`. Changing `POSTGRES_USER` / `POSTGRES_PASSWORD` after the database volume already exists requires recreating the volume (`docker compose down -v`) or the old role/password remains.

### 7. Build and start

```bash
docker compose up --build -d
docker compose ps
docker compose logs -f
```

Wait until `database`, `backend`, and `frontend` are healthy.

### 8. Verify

On the instance:

```bash
curl http://127.0.0.1:5000/health
curl http://127.0.0.1:3000/api/incidents
```

In a browser:

```text
http://YOUR_EC2_PUBLIC_IP:3000
```

### 9. Day-2 operations

```bash
docker compose ps
docker compose logs -f backend
docker compose restart
docker compose down              # stop containers; keep DB volume
docker compose down -v          # stop and delete DB data
docker compose up --build -d    # rebuild after code changes
```

### Notes for this deployment style

- The app listens on host port **3000** (`FRONTEND_PORT` → container `80`). To serve on port 80 instead, open `80` in the security group and set `FRONTEND_PORT=80` in `.env`.
- This is a training-friendly Compose deploy on one VM. Production hardening would add HTTPS (Caddy/nginx + Let’s Encrypt or an ALB), managed secrets, backups, and preferably a managed database (RDS) instead of Postgres on the same instance.
