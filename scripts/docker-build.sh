#!/usr/bin/env bash
set -euo pipefail

COMMIT=$(git rev-parse --short HEAD)
IMAGE="instabot:${COMMIT}"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Building Docker image: ${IMAGE}"

docker build -t "${IMAGE}" -t "instabot:latest" .

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Build complete: ${IMAGE}"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Tagged as: instabot:latest"
