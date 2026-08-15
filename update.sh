#!/usr/bin/env bash
# Safely update Heimdall on Kubernetes and prune unused local images when possible.
# Creates a local rollback backup first, then asks whether to keep it.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
NS=heimdall

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

ask_backup_retention() {
  local dir="$1"
  if [[ ! -d "${dir}" ]]; then
    return 0
  fi
  if [[ ! -t 0 ]]; then
    echo "No interactive terminal — keeping backup at ${dir}"
    return 0
  fi
  echo
  local reply=""
  read -r -p "Update succeeded. Keep rollback backup at ${dir}? [Y/n] " reply || true
  case "${reply:-Y}" in
    n|N|no|NO)
      rm -rf "${dir}"
      rmdir backups 2>/dev/null || true
      echo "Backup deleted."
      ;;
    *)
      echo "Backup kept."
      echo "  See ${dir}/RESTORE.txt if you need to roll back."
      ;;
  esac
}

create_backup() {
  BACKUP_DIR="${ROOT}/backups/update-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "${BACKUP_DIR}"
  echo "==> Creating rollback backup in ${BACKUP_DIR} ..."
  cp -a "${ROOT}/deploy.yaml" "${BACKUP_DIR}/" 2>/dev/null || true
  kubectl -n "$NS" get deploy,svc,pvc -o yaml >"${BACKUP_DIR}/resources.yaml" 2>/dev/null || true

  local pod
  pod="$(kubectl -n "$NS" get pod -l app=heimdall -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  if [[ -n "${pod}" ]]; then
    echo "    Archiving /config from pod ${pod} ..."
    kubectl -n "$NS" exec "${pod}" -- tar -C /config -czf - . >"${BACKUP_DIR}/config.tar.gz" \
      || echo "    Warning: could not archive pod /config"
  else
    echo "    Warning: no running Heimdall pod — skipped PVC data archive"
  fi

  cat >"${BACKUP_DIR}/RESTORE.txt" <<EOF
Heimdall k8s rollback (data):

  # Recreate / restore PVC contents into a running pod, e.g.:
  POD=\$(kubectl -n heimdall get pod -l app=heimdall -o jsonpath='{.items[0].metadata.name}')
  kubectl -n heimdall exec -i "\$POD" -- tar -C /config -xzf - < ${BACKUP_DIR}/config.tar.gz
  kubectl -n heimdall rollout restart deployment/heimdall

Manifests snapshot: ${BACKUP_DIR}/resources.yaml
EOF
  echo "Backup ready: ${BACKUP_DIR}"
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

create_backup

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
echo "Update finished. PVC data was left untouched (backup is a point-in-time copy)."
echo "  kubectl -n heimdall get svc heimdall"
ask_backup_retention "${BACKUP_DIR}"
