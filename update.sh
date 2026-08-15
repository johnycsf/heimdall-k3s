#!/usr/bin/env bash
# Safely update Heimdall on Kubernetes and prune unused local images when possible.
# Safe to run while the app is live (rollout recreates the pod with the new image).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

need kubectl

if ! kubectl get storageclass longhorn >/dev/null 2>&1; then
  echo "Longhorn StorageClass not found — fix storage before updating." >&2
  exit 1
fi

if [[ "${I_UNDERSTAND_THIS_IS_A_FRESH_INSTALL:-}" != "yes" ]]; then
  if kubectl -n heimdall get deploy heimdall >/dev/null 2>&1; then
    img="$(kubectl -n heimdall get deploy heimdall -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)"
    if [[ "${img}" == *linuxserver* ]] || [[ "${img}" == *lscr.io* ]]; then
      echo "Refusing to update a LinuxServer Heimdall Deployment. See BREAKING-CHANGES.md" >&2
      exit 1
    fi
  else
    echo "Heimdall is not installed yet. Run ./install.sh first." >&2
    exit 1
  fi
fi

if command -v docker >/dev/null 2>&1; then
  BUILDER=(docker)
elif command -v podman >/dev/null 2>&1; then
  BUILDER=(podman)
else
  echo "Need docker or podman to rebuild heimdall:local." >&2
  exit 1
fi

echo "==> Rebuilding heimdall:local..."
"${BUILDER[@]}" build -t heimdall:local "${ROOT}"

if command -v k3s >/dev/null 2>&1; then
  echo "==> Importing image into k3s..."
  "${BUILDER[@]}" save heimdall:local | sudo k3s ctr images import -
elif command -v kind >/dev/null 2>&1 && kind get clusters 2>/dev/null | grep -q .; then
  echo "==> Loading image into kind..."
  if [[ "${BUILDER[0]}" == docker ]]; then
    kind load docker-image heimdall:local
  else
    "${BUILDER[@]}" save heimdall:local | kind load image-archive /dev/stdin
  fi
fi

echo "==> Applying manifests..."
kubectl apply -f "${ROOT}/deploy.yaml"
echo "==> Rolling out new pods..."
kubectl -n heimdall rollout restart deployment/heimdall
kubectl -n heimdall rollout status deployment/heimdall --timeout=180s

echo "==> Pruning unused images on this machine (dangling/unused only)..."
if command -v k3s >/dev/null 2>&1; then
  sudo k3s crictl rmi --prune 2>/dev/null || echo "(skipped k3s prune — need sudo or crictl)"
elif command -v docker >/dev/null 2>&1; then
  docker image prune -f
fi

echo
echo "Update finished. PVC data was left untouched."
echo "  kubectl -n heimdall get svc heimdall"
