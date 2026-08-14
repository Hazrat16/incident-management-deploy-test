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
