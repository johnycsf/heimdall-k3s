#!/usr/bin/env bash
# Install Heimdall on a Kubernetes cluster with Longhorn storage.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

need kubectl

if ! kubectl get storageclass longhorn >/dev/null 2>&1; then
  cat <<'EOF' >&2
Longhorn storage class not found.

Install Longhorn first (one-time, shared by these homelab apps):

  helm repo add longhorn https://charts.longhorn.io
  helm repo update
  helm install longhorn longhorn/longhorn \
    --namespace longhorn-system --create-namespace

Wait until pods are ready:

  kubectl -n longhorn-system get pod

Then re-run this script.
EOF
  exit 1
fi

echo "Applying Heimdall manifests..."
kubectl apply -f "${ROOT}/deploy.yaml"

echo "Waiting for Heimdall to become ready..."
kubectl -n heimdall rollout status deployment/heimdall --timeout=180s

echo
echo "Heimdall is installed."
echo "Get the service address with:"
echo "  kubectl -n heimdall get svc heimdall"
echo
echo "Open http://<EXTERNAL-IP>/ in your browser."
echo "(HTTPS also works on port 443 with a self-signed cert.)"
