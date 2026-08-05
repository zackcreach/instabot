#!/usr/bin/env bash
set -euo pipefail

IMAGE="${1:-instabot:latest}"
EXPECTED_POSTGRES_MAJOR="18"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "Deploying ${IMAGE}..."

if ! docker inspect instabot_db >/dev/null 2>&1; then
  log "ERROR: instabot_db is not running; routine deployment will not create the database"
  exit 1
fi

running_version_number=$(docker exec instabot_db psql -U postgres -d instabot_prod -Atqc "SHOW server_version_num")
running_postgres_major="${running_version_number:0:2}"

if [[ "$running_postgres_major" != "$EXPECTED_POSTGRES_MAJOR" ]]; then
  log "ERROR: configured PostgreSQL major ${EXPECTED_POSTGRES_MAJOR} differs from running major ${running_postgres_major}"
  exit 1
fi

log "Running database migrations..."
docker compose -f docker-compose.yml run --rm --no-deps instabot /app/bin/migrate

log "Recreating the application container..."
docker compose -f docker-compose.yml up -d --no-deps --force-recreate instabot

log "Waiting for health check..."
for attempt in {1..60}; do
  health_status=$(docker inspect instabot --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}')

  if [[ "$health_status" == "healthy" ]]; then
    log "Deployment successful"
    docker compose -f docker-compose.yml ps instabot
    exit 0
  fi

  if [[ "$health_status" == "unhealthy" || "$attempt" == "60" ]]; then
    log "ERROR: Deployment failed with application status ${health_status}"
    docker compose -f docker-compose.yml logs instabot
    exit 1
  fi

  sleep 2
done
