#!/usr/bin/env bash
# Install / reconfigure Heimdall on Kubernetes (interactive).
# Builds from Dockerfile (official php:apache + upstream Heimdall) — no LinuxServer image.
# Re-run anytime to change StorageClass preference or replica count.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/deps.sh
source "${ROOT}/scripts/deps.sh"

ui_banner "Heimdall" "Kubernetes · storage + replicas chosen interactively"
ui_steps_init 6

ui_step "Checking host dependencies"
ensure_host_deps heimdall-k8s sqlite3

ui_step "StorageClass"
configure_k8s_storage

ui_step "Replica count"
configure_k8s_replicas heimdall

ALREADY=false
if kubectl -n heimdall get deploy heimdall >/dev/null 2>&1; then
  ALREADY=true
  ui_info "Existing Heimdall Deployment found — refreshing manifests/replicas"
fi

if [[ "${I_UNDERSTAND_THIS_IS_A_FRESH_INSTALL:-}" != "yes" ]]; then
  if [[ "${ALREADY}" == true ]]; then
    img="$(kubectl -n heimdall get deploy heimdall -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)"
    if [[ "${img}" == *linuxserver* ]] || [[ "${img}" == *lscr.io* ]]; then
      ui_err "Heimdall is still deployed with a LinuxServer image."
      cat <<'EOF' >&2

git pull alone is safe. Re-running install.sh is NOT an in-place upgrade.
See BREAKING-CHANGES.md

Options:
  1) Leave the cluster as-is.
  2) Backup, delete the heimdall namespace/PVC, install fresh.
  3) Only if you accept a fresh install:
       I_UNDERSTAND_THIS_IS_A_FRESH_INSTALL=yes ./manage.sh install
EOF
      exit 1
    fi
  fi
else
  ui_warn "Override set: I_UNDERSTAND_THIS_IS_A_FRESH_INSTALL=yes — continuing."
fi

if command -v docker >/dev/null 2>&1; then
  BUILDER=(docker)
elif command -v podman >/dev/null 2>&1; then
  BUILDER=(podman)
else
  ui_err "Need docker or podman to build the Heimdall image from Dockerfile."
  exit 1
fi

ui_step "Building heimdall:local"
ui_run "Build image" "${BUILDER[@]}" build -t heimdall:local "${ROOT}"

ui_step "Loading image into the cluster (when possible)"
loaded=false
if command -v k3s >/dev/null 2>&1; then
  echo -n "${UI_DIM}…${UI_RESET} Importing image into k3s "
  if "${BUILDER[@]}" save heimdall:local | sudo k3s ctr images import - >/dev/null 2>&1; then
    echo "${UI_GREEN}done${UI_RESET}"
    loaded=true
  else
    echo "${UI_YELLOW}skipped${UI_RESET}"
  fi
elif command -v kind >/dev/null 2>&1 && kind get clusters 2>/dev/null | grep -q .; then
  if [[ "${BUILDER[0]}" == docker ]]; then
    ui_run "kind load docker-image" kind load docker-image heimdall:local
  else
    "${BUILDER[@]}" save heimdall:local | kind load image-archive /dev/stdin
  fi
  loaded=true
fi

if [[ "$loaded" != true ]]; then
  ui_warn "Could not auto-load heimdall:local into the cluster"
  ui_info "On single-node clusters, imagePullPolicy: Never may still work after a local build"
fi

ui_step "Applying manifests and scaling"
ui_run "kubectl apply" apply_manifest "${ROOT}/deploy.yaml"
apply_saved_replicas heimdall
ui_run "Wait for rollout" kubectl -n heimdall rollout status deployment/heimdall --timeout=180s

echo
ui_ok "Heimdall is installed (replicas=${CHOSEN_REPLICAS:-1}, storage=${CHOSEN_STORAGE_CLASS:-})"
ui_info "Service: kubectl -n heimdall get svc heimdall"
ui_info "Open http://<EXTERNAL-IP>/ then set APP_URL in deploy.yaml if needed"
ui_info "Re-run ./manage.sh anytime to change replicas or storage preference"
