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
kubectl apply -n "$NAMESPACE" -f "$ROOT_DIR/test/pod-runtime.yaml"
set +x

echo "[wait] Waiting for pod/universal-runtime to complete..."
kubectl wait -n "$NAMESPACE" --for=condition=Ready pod/universal-runtime --timeout=300s || true
kubectl wait -n "$NAMESPACE" --for=condition=ContainersReady pod/universal-runtime --timeout=300s || true
kubectl wait -n "$NAMESPACE" --for=condition=PodScheduled pod/universal-runtime --timeout=300s || true

STATUS=$(kubectl get pod -n "$NAMESPACE" universal-runtime -o jsonpath='{.status.phase}')
echo "[status] Pod status: $STATUS"

LOGS=$(kubectl logs -n "$NAMESPACE" pod/universal-runtime)
echo "$LOGS"

if echo "$LOGS" | grep -q "torch import ok"; then
	echo "[ok] Torch import succeeded"
else
	echo "[fail] Torch import did not succeed"; exit 1
fi

if echo "$LOGS" | grep -q "cuda_available= True"; then
	echo "[ok] CUDA available on GPU node"
else
	echo "[warn] CUDA not available; ensure GPU scheduling and drivers are present"
fi

echo "[cleanup] Deleting pod"
kubectl delete -n "$NAMESPACE" -f "$ROOT_DIR/test/pod-runtime.yaml" --wait=true
