#!/usr/bin/env bash
set -euo pipefail

# Multi-arch build script for the universal image
# - Defaults to linux/amd64 (set PLATFORMS to add linux/arm64 later)
# - Tags only :latest by default
# - Pushes to quay.io/bgallagher/universal-image (configure with IMAGE_REPO)
#
# Requirements:
# - Docker with Buildx (Docker Desktop on Mac includes this)
# - Logged in to quay.io (`docker login quay.io`)
#
# Environment overrides:
#   IMAGE_REPO   (default: quay.io/bgallagher/universal-image)
#   IMAGE_TAG    (default: latest)
#   PLATFORMS    (default: linux/amd64)
#   PUSH         (default: true; set to false to load a single-arch image locally)
#   EXTRA_TAGS   (optional, space-separated list of additional tags to push)
#   LOAD_PLATFORM (optional, overrides local load platform when PUSH=false)

IMAGE_REPO=${IMAGE_REPO:-quay.io/bgallagher/universal-image}
IMAGE_TAG=${IMAGE_TAG:-latest}
PLATFORMS=${PLATFORMS:-linux/amd64}
PUSH=${PUSH:-true}
EXTRA_TAGS=${EXTRA_TAGS:-}

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
BUILD_CONTEXT="$ROOT_DIR/image"

# Base image used by our Dockerfile (for informational checks only)
BASE_IMAGE=${BASE_IMAGE:-quay.io/opendatahub/workbench-images:cuda-jupyter-minimal-ubi9-python-3.12-2025a_20250903}

echo "[info] Build context: $BUILD_CONTEXT"
echo "[info] Target repo:   $IMAGE_REPO"
echo "[info] Tag:           $IMAGE_TAG (and EXTRA_TAGS if set)"
echo "[info] Platforms:     $PLATFORMS"
echo "[info] Base image:    $BASE_IMAGE"

# Ensure buildx builder exists and is selected
if ! docker buildx ls | grep -q "universal-builder"; then
	echo "[buildx] Creating and selecting builder 'universal-builder'"
	docker buildx create --use --name universal-builder >/dev/null 2>&1 || docker buildx use universal-builder
else
	echo "[buildx] Using existing builder 'universal-builder'"
	docker buildx use universal-builder
fi

FULL_PRIMARY_TAG="$IMAGE_REPO:$IMAGE_TAG"
ALL_TAG_ARGS=( -t "$FULL_PRIMARY_TAG" )

# Add any extra tags requested
if [ -n "$EXTRA_TAGS" ]; then
	for t in $EXTRA_TAGS; do
		ALL_TAG_ARGS+=( -t "$IMAGE_REPO:$t" )
	done
fi

if [ "$PUSH" = "true" ]; then
	echo "[buildx] Building and pushing images to $IMAGE_REPO"
	set -x
	docker buildx build \
		--platform "$PLATFORMS" \
		"${ALL_TAG_ARGS[@]}" \
		--provenance=true --sbom=true \
		--push \
		"$BUILD_CONTEXT"
	set +x
	echo "[done] Pushed: $FULL_PRIMARY_TAG ${EXTRA_TAGS:+and $EXTRA_TAGS}"
else
	# Load a single-arch image locally for quick testing
	if [ -n "${LOAD_PLATFORM:-}" ]; then
		SELECTED_PLATFORM="$LOAD_PLATFORM"
	else
		# pick the first platform from PLATFORMS if provided, else fall back to host arch
		FIRST_PLATFORM=$(printf "%s" "$PLATFORMS" | cut -d',' -f1)
		if [ -n "$FIRST_PLATFORM" ]; then
			SELECTED_PLATFORM="$FIRST_PLATFORM"
		else
			HOST_ARCH=$(uname -m)
			case "$HOST_ARCH" in
				arm64|aarch64) SELECTED_PLATFORM=linux/arm64 ;;
				x86_64|amd64)  SELECTED_PLATFORM=linux/amd64 ;;
				*)            SELECTED_PLATFORM=linux/amd64 ;;
			esac
		fi
	fi
	echo "[buildx] Loading locally for $SELECTED_PLATFORM (no push)"
	set -x
	# Stream image tar to docker load to avoid closed-pipe issues with --load
	docker buildx build \
		--platform "$SELECTED_PLATFORM" \
		"${ALL_TAG_ARGS[@]}" \
		--output=type=docker,dest=- \
		"$BUILD_CONTEXT" | docker load
	set +x
	echo "[done] Loaded locally: $FULL_PRIMARY_TAG ${EXTRA_TAGS:+and $EXTRA_TAGS}"
fi

cat << 'USAGE'

Usage examples:

# Build and push amd64 latest to Quay (requires docker login):
IMAGE_REPO=quay.io/bgallagher/universal-image IMAGE_TAG=latest PUSH=true bash universal-image/test/build_multiarch.sh

# Build and push amd64 + arm64 (when base supports arm64):
PLATFORMS=linux/amd64,linux/arm64 PUSH=true bash universal-image/test/build_multiarch.sh

# Build but do not push; load only your host arch locally:
PUSH=false IMAGE_TAG=local bash universal-image/test/build_multiarch.sh

# Build but do not push; force local load to amd64 on Apple Silicon:
PUSH=false LOAD_PLATFORM=linux/amd64 IMAGE_TAG=local bash universal-image/test/build_multiarch.sh

Notes:
- Image reference is quay.io/bgallagher/universal-image
- For GPU clusters, ensure nodes can pull Quay images; otherwise push to a registry accessible by the cluster.
USAGE
