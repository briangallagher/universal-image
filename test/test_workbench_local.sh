#!/usr/bin/env bash
set -euo pipefail

IMAGE_TAG=${1:-universal-image:dev}
ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)

echo "[build] Building $IMAGE_TAG from $ROOT_DIR/image (platform linux/amd64)"
docker build --platform linux/amd64 -t "$IMAGE_TAG" "$ROOT_DIR/image"

echo "[run] Launching workbench (no args) — Jupyter should start and listen on 8888"
echo "[info] Press Ctrl+C to stop."
exec docker run --rm -p 8888:8888 "$IMAGE_TAG"
