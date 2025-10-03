#!/usr/bin/env bash
set -euo pipefail

IMAGE_TAG=${1:-universal-image:dev}
ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)

if ! docker image inspect "$IMAGE_TAG" >/dev/null 2>&1; then
	echo "[build] Building $IMAGE_TAG from $ROOT_DIR/image (platform linux/amd64)"
	docker build --platform linux/amd64 -t "$IMAGE_TAG" "$ROOT_DIR/image"
fi

echo "[run] Runtime mode: executing provided command (no notebook)"
set -x
docker run --rm -e RUNTIME_MODE=true "$IMAGE_TAG" python -c "import torch; print('torch import ok, cuda_available=', torch.cuda.is_available())"
set +x

echo "[note] On Mac without GPU, cuda_available will likely be False."
echo "[k8s] To validate with GPUs on Kubernetes, run a Pod/Job with nvidia.com/gpu and a similar python command."
