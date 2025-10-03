# Universal Image - Design Decisions

## Core principles
- Base on minimal workbench image with CUDA 12.8: `quay.io/opendatahub/workbench-images:cuda-jupyter-minimal-ubi9-python-3.12-2025a_20250903`.
- Combine capabilities of minimal workbench and runtime images; default to workbench behavior.
- Duplicates principle: prefer dependencies provided by the base; add only what is missing from runtime.
- Mode selection by invocation style:
  - No command provided → workbench mode (launch `start-notebook.sh`).
  - Command provided → runtime mode (exec the provided command/headless).
- Preserve runtime behavior for OS repos (CUDA, Mellanox OFED), driver floors, and IB/RDMA packages.
- Support linux/amd64 and linux/arm64 builds when possible; verify runtime compatibility.

## Features
- Python 3.12 (from base minimal workbench image)
- CUDA 12.8 runtime (from base); optional nvcc 12.8 (commented in universal Dockerfile if needed)
- JupyterLab minimal stack with Elyra addons and notebook UX (from base)
- OpenShift `oc` CLI and PDF export tooling (from base)
- RDMA/IB userspace libraries (from universal image, following runtime repos)
- Training/ML Python stack (from universal image):
  - torch==2.8.0 (cu128 wheels)
  - flash-attn==2.8.3 (mandatory; currently enforced for amd64 builds)
  - accelerate, transformers, peft, datasets, HF hub, Deepspeed, TRL
  - CUDA Python wheels (nvidia-* cu12.8 series as applicable)
- Entry behavior control (from universal entrypoint):
  - Default CMD `start-notebook.sh` (workbench)
  - Args provided → exec args (runtime)

## Behavior expectations
- Workbench mode: identical UX to minimal (JupyterLab, Elyra addons, disabled announcements, kernel label updates). Default CMD remains `start-notebook.sh`.
- Runtime mode: headless, container runs the command/args provided by the platform (no notebook).

## Dependency approach
- OS: keep minimal’s UBI9 system state; add runtime’s RDMA/IB packages and (if needed) CUDA dev tools matching 12.8. Avoid downgrades/duplicates.
- Python: do not re-install minimal’s pinned Jupyter stack. Layer runtime’s ML/training set (torch 2.8.0 + cu128, flash-attn 2.8.3, HF stack, Deepspeed, etc.) using pip.
- Binaries: keep `oc` from minimal; rely on base CUDA; avoid redundant binary downloads.

## Why this image does not use a Pipfile/lock
- Avoid resolver mixing: minimal uses `uv` with a lock for its Jupyter base; adding a second lock (Pipfile.lock) risks conflicts and backtracking across resolvers.
- Precise CUDA control: torch/cu128 and flash-attn require strict versioning/order and vendor indexes; explicit `pip` steps keep control over install order and indexes.
- Wheel availability: flash-attn and some CUDA wheels are arch/ABI‑specific; locks can break on non‑amd64 or when wheels lag. Explicit pins with guarded installs reduce surprises.
- Simplicity: fewer moving parts in the universal layer; reproducibility is achieved via exact pins and the stable minimal base. (We can add a generated requirements lock in the future if needed.)

## Inline pins vs lockfile (drawbacks and option)
- Drawbacks of inline pins in Dockerfile:
  - Less reproducibility across time than a full lock (hashes, transitive pins).
  - Harder to audit SBOMs against a single lock source of truth.
  - Updates require editing Dockerfile and rebuilding to test resolution changes.
- Why acceptable here:
  - Minimal base already locks the Jupyter layer via uv; universal adds a small, well-pinned training set with strict versions and order.
  - CUDA/FA/torch require explicit index control and sequencing that tend to fight generic lock resolvers.
- Lockfile option:
  - We could generate a `requirements.txt` with hashes (pip-compile/uv) for the universal additions only and install with `--require-hashes`. This keeps base lock intact while giving the universal layer a tight lock.
  - Trade-off: occasional refresh needed when wheels change; still must keep torch/cu128 and FA index ordering explicit.

## Risks and mitigations
- CUDA duplication/version drift: rely on base CUDA 12.8; install only missing dev tools (e.g., nvcc) if needed. Pin versions.
- Resolver split (uv vs pip): do not re-run uv on combined env; add runtime deps with pip only to avoid conflicting locks.
- FlashAttention/torch coupling: ensure torch/cu128 and FA wheel match CUDA 12.8. Rebuild/pin if base CUDA changes. Note: FA currently enforced on amd64.
- Image size growth: clear caches (`dnf`, `pip`), avoid re-installation, minimize layers.
- Non-IB clusters: installing OFED libs should be inert; do not enable services by default.

## Entry strategy
- Provide a small POSIX entrypoint wrapper. If args are present, `exec "$@"`; otherwise `exec start-notebook.sh`.
- Set ENTRYPOINT to wrapper; set CMD to `start-notebook.sh`. This preserves workbench default while allowing runtime override by passing a command.

## Testing
- Local (Mac, no GPU):
  - Workbench: run container without args; Jupyter should start and be reachable.
  - Runtime: run `python -c "import torch; print(torch.cuda.is_available())"` expecting `False` locally; import should succeed.
- Kubernetes (GPU):
  - Workbench: launch with notebook service if desired.
  - Runtime: run a Pod/Job with `nvidia.com/gpu` requesting 1 GPU and a simple torch CUDA smoke test; validate NCCL env if needed.

## Publication and compliance
- Keep NVIDIA driver floors (`NVIDIA_REQUIRE_CUDA`).
- Use the same external repos and SBOM/signing practices as the current runtime.

## Out of scope / TBD
- Exact registry/repo/tag for publishing.
- Whether to include `nvcc` by default or behind a build-arg toggle based on need.
