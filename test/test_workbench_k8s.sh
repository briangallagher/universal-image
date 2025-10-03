#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=${NAMESPACE:-default}
IMAGE_TAG=${1:-universal-image:dev}
ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)

# Ensure image exists locally; advise load into cluster if needed
if ! docker image inspect "$IMAGE_TAG" >/dev/null 2>&1; then
	echo "[build] Building $IMAGE_TAG from $ROOT_DIR/image"
	docker build -t "$IMAGE_TAG" "$ROOT_DIR/image"
	echo "[note] If your cluster cannot pull local images, push to a registry or use kind load." 
fi

set -x
kubectl apply -n "$NAMESPACE" -f "$ROOT_DIR/test/pod-workbench.yaml"
set +x

echo "[wait] Waiting for pod/universal-workbench to be Running..."
kubectl wait -n "$NAMESPACE" --for=condition=Ready pod/universal-workbench --timeout=300s

echo "[logs] Checking Jupyter startup logs for token URL"
LOGS=$(kubectl logs -n "$NAMESPACE" pod/universal-workbench)
if echo "$LOGS" | grep -E "http://.*:8888/\?token=" >/dev/null; then
	echo "[ok] Jupyter token URL found in logs"
else
	echo "[warn] Jupyter token URL not found; check service/port-forward manually"
fi

echo "[cleanup] Deleting pod"
kubectl delete -n "$NAMESPACE" -f "$ROOT_DIR/test/pod-workbench.yaml" --wait=true
