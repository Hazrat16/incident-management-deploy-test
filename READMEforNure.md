# Incident Management Docker Lab — Mentor Edition

A complete three-service application for teaching Docker and Docker Compose:

- **Frontend:** React + Vite, built into a production Nginx image
- **Backend:** Node.js + Express REST API
- **Database:** PostgreSQL 16

## Architecture

```text
Browser -> localhost:3000 -> Nginx frontend
                              |
                              +-- /api -> backend:5000 -> database:5432
```

The browser only needs the frontend URL. Nginx serves the React application and proxies API requests to the backend using the Docker Compose service name `backend`. The backend connects to PostgreSQL using the service name `database`.

## Prerequisites

Install:

- Docker Desktop on macOS or Windows, or Docker Engine on Linux
- Docker Compose v2

Verify:

```bash
docker --version
docker compose version
```

## First run

From the project root:

```bash
cp .env.example .env
docker compose up --build
```

On Windows PowerShell:

```powershell
Copy-Item .env.example .env
docker compose up --build
```

Wait until all three services are healthy, then open:

- Frontend: http://localhost:3000
- Backend health: http://localhost:5000/health
- Incidents API: http://localhost:5000/api/incidents

## Run in detached mode

```bash
docker compose up --build -d
docker compose ps
```

## Observe logs

All services:

```bash
docker compose logs -f
```

One service:

```bash
docker compose logs -f backend
docker compose logs -f frontend
docker compose logs -f database
```

## Test the API

Create an incident:

```bash
curl -X POST http://localhost:5000/api/incidents \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Payment service unavailable",
    "description": "Customers cannot complete checkout.",
    "severity": "critical"
  }'
```

List incidents:

```bash
curl http://localhost:5000/api/incidents
```

Update incident status; replace `1` with a valid incident ID:

```bash
curl -X PATCH http://localhost:5000/api/incidents/1/status \
  -H "Content-Type: application/json" \
  -d '{"status":"resolved"}'
```

## Stop the application

Stop containers while preserving PostgreSQL data:

```bash
docker compose down
```

Start again and verify the incidents still exist:

```bash
docker compose up -d
```

## Delete all application data

This removes containers, the network, and the PostgreSQL named volume:

```bash
docker compose down -v
```

Use this only when you want a completely fresh database.

## Force a rebuild

```bash
docker compose build --no-cache
docker compose up -d
```

## Useful inspection commands

```bash
docker compose ps
docker images
docker volume ls
docker network ls
docker inspect incident-backend
docker inspect incident-postgres-data
```

Enter a running container:

```bash
docker compose exec backend sh
docker compose exec frontend sh
docker compose exec database sh
```

Connect to PostgreSQL:

```bash
docker compose exec database psql \
  -U incident_user \
  -d incidentdb
```

Then run:

```sql
SELECT * FROM incidents ORDER BY created_at DESC;
\q
```

## Common problems

### Port already in use

Change values in `.env`:

```env
BACKEND_PORT=5001
FRONTEND_PORT=3001
```

Then recreate the services:

```bash
docker compose down
docker compose up --build -d
```

### Backend cannot connect to PostgreSQL

Inside Compose, `DB_HOST` must be `database`, not `localhost`. Each container has its own network namespace, so `localhost` means the current container.

Check:

```bash
docker compose ps
docker compose logs database
docker compose logs backend
```

### Frontend opens but API requests fail

Check the frontend Nginx proxy and backend health:

```bash
curl http://localhost:5000/health
docker compose logs frontend
docker compose logs backend
```

### Changes do not appear

This is a production-style image, not a hot-reload development environment. Rebuild after source-code changes:

```bash
docker compose up --build -d
```

## Teaching notes

The mentor solution demonstrates:

1. Dependency-layer caching in both Dockerfiles
2. A multi-stage frontend build
3. A non-root backend process
4. Service discovery through Compose DNS
5. A PostgreSQL named volume
6. Health checks and startup ordering
7. Reverse proxying from Nginx to the backend
8. Environment-based configuration
9. Graceful backend shutdown
10. Restart policies and an isolated bridge network

For the student version, remove:

- `backend/Dockerfile`
- `backend/.dockerignore`
- `frontend/Dockerfile`
- `frontend/.dockerignore`
- `frontend/nginx.conf`
- `compose.yaml`

Keep `.env.example`, application source code, and `STUDENT_ASSIGNMENT.md`.
