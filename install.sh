#!/usr/bin/env bash
# Install Heimdall on a Kubernetes cluster (storage class chosen at install time).
# Builds from Dockerfile (official php:apache + upstream Heimdall) — no LinuxServer image.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=deps.sh
source "${ROOT}/deps.sh"
ensure_host_deps heimdall-k8s sqlite3
configure_k8s_storage

if [[ "${I_UNDERSTAND_THIS_IS_A_FRESH_INSTALL:-}" != "yes" ]]; then
  if kubectl -n heimdall get deploy heimdall >/dev/null 2>&1; then
    img="$(kubectl -n heimdall get deploy heimdall -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)"
    if [[ "${img}" == *linuxserver* ]] || [[ "${img}" == *lscr.io* ]]; then
      cat <<'EOF' >&2
Refusing to continue: Heimdall is still deployed with a LinuxServer image.

git pull alone is safe. Re-running install.sh is NOT an in-place upgrade.

See BREAKING-CHANGES.md

Options:
  1) Leave the cluster as-is.
  2) Backup, delete the heimdall namespace/PVC, install fresh.
  3) Only if you accept a fresh install:
       I_UNDERSTAND_THIS_IS_A_FRESH_INSTALL=yes ./install.sh
EOF
      exit 1
    fi
  fi
else
  echo "Override set: I_UNDERSTAND_THIS_IS_A_FRESH_INSTALL=yes — continuing."
fi

if command -v docker >/dev/null 2>&1; then
  BUILDER=(docker)
elif command -v podman >/dev/null 2>&1; then
  BUILDER=(podman)
else
  echo "Need docker or podman to build the Heimdall image from Dockerfile." >&2
  exit 1
fi

echo "Building heimdall:local from official php:apache + Heimdall upstream..."
"${BUILDER[@]}" build -t heimdall:local "${ROOT}"

# Load into the local cluster runtime when possible (k3s / kind / plain containerd)
loaded=false
if command -v k3s >/dev/null 2>&1; then
  echo "Importing image into k3s..."
  "${BUILDER[@]}" save heimdall:local | sudo k3s ctr images import -
  loaded=true
elif command -v kind >/dev/null 2>&1 && kind get clusters 2>/dev/null | grep -q .; then
  echo "Loading image into kind..."
  if [[ "${BUILDER[0]}" == docker ]]; then
    kind load docker-image heimdall:local
  else
    "${BUILDER[@]}" save heimdall:local | kind load image-archive /dev/stdin
  fi
  loaded=true
fi

if [[ "$loaded" != true ]]; then
  cat <<'EOF'
Could not auto-load heimdall:local into the cluster.

For a single-node cluster where the kubelet shares your container runtime,
imagePullPolicy: Never may still work after the local build.

Otherwise push the image to a registry you control and change deploy.yaml:
  image: your-registry/heimdall:tag
  imagePullPolicy: IfNotPresent
EOF
fi

echo "Applying Heimdall manifests..."
apply_manifest "${ROOT}/deploy.yaml"

echo "Waiting for Heimdall to become ready..."
kubectl -n heimdall rollout status deployment/heimdall --timeout=180s

echo
echo "Heimdall is installed."
echo "Get the service address with:"
echo "  kubectl -n heimdall get svc heimdall"
echo
echo "Open http://<EXTERNAL-IP>/ in your browser."
echo "Then set APP_URL in deploy.yaml to that URL and re-apply if needed."
