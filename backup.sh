#!/usr/bin/env bash
# Disaster-recovery backup/restore with incremental rsync snapshots (k8s).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
NS=heimdall
STACK_ID="heimdall-k8s"

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1" >&2; exit 1; }
}

need_rsync() {
  command -v rsync >/dev/null 2>&1 || {
    echo "Missing: rsync (needed for incremental snapshots)." >&2
    exit 1
  }
}

usage() {
  cat <<EOF
Usage:
  ./backup.sh --dest /path/to/backup-root [--keep N]
  ./backup.sh --restore --from /path/to/backup-root-or-snapshot
  ./backup.sh --help

Disaster-recovery backups (separate from update.sh rollback tarballs).

  --dest DIR    Create a new incremental snapshot under DIR.
                Uses rsync hardlinks against the previous snapshot so
                unchanged files are not duplicated on disk.
  --keep N      After backup, keep only the newest N snapshots (default: no prune).
  --restore     Restore into this deployment from --from.
  --from PATH   Backup root (uses latest/) or a specific snapshots/TIMESTAMP dir.

Fresh-machine workflow:
  1) Install this stack on the new host (./install.sh) so runtime exists.
  2) ./backup.sh --restore --from /mnt/usb/my-backups
  3) Script replaces data/secrets and finishes app-specific repair (e.g. Nextcloud scan).
EOF
}

MODE=""
DEST=""
FROM=""
KEEP=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest)
      [[ $# -ge 2 ]] || { echo "--dest needs a path" >&2; exit 1; }
      DEST="$2"; MODE="${MODE:-backup}"; shift 2 ;;
    --from)
      [[ $# -ge 2 ]] || { echo "--from needs a path" >&2; exit 1; }
      FROM="$2"; shift 2 ;;
    --restore)
      MODE="restore"; shift ;;
    --keep)
      [[ $# -ge 2 ]] || { echo "--keep needs a number" >&2; exit 1; }
      KEEP="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

stamp_now() { date +%Y%m%d-%H%M%S; }

resolve_snapshot_dir() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    echo "Not found: $path" >&2
    exit 1
  fi
  path="$(cd "$path" && pwd)"
  if [[ -f "${path}/META.txt" ]]; then
    printf '%s\n' "$path"
    return 0
  fi
  if [[ -L "${path}/latest" ]]; then
    local target=""
    if target="$(readlink -f "${path}/latest" 2>/dev/null)"; then
      :
    else
      target="$(readlink "${path}/latest")"
      [[ "$target" == /* ]] || target="${path}/${target}"
    fi
    if [[ -f "${target}/META.txt" ]]; then
      printf '%s\n' "$(cd "$target" && pwd)"
      return 0
    fi
  fi
  # newest snapshots/*
  local newest
  newest="$(ls -1dt "${path}"/snapshots/* 2>/dev/null | head -1 || true)"
  if [[ -n "$newest" && -f "${newest}/META.txt" ]]; then
    printf '%s\n' "$(cd "$newest" && pwd)"
    return 0
  fi
  echo "No usable snapshot under: $path" >&2
  echo "Expected META.txt in a snapshot dir, or a backup root with latest/ / snapshots/." >&2
  exit 1
}

prepare_snapshot_dirs() {
  local dest="$1"
  mkdir -p "${dest}/snapshots"
  SNAP_NAME="$(stamp_now)"
  SNAP_DIR="${dest}/snapshots/${SNAP_NAME}"
  mkdir -p "${SNAP_DIR}"
  PREV_LINK=""
  if [[ -L "${dest}/latest" ]]; then
    PREV_LINK="$(readlink "${dest}/latest")"
    if [[ "${PREV_LINK}" != /* ]]; then
      PREV_LINK="${dest}/${PREV_LINK}"
    fi
  fi
}

finalize_snapshot() {
  local dest="$1"
  ln -sfn "snapshots/${SNAP_NAME}" "${dest}/latest"
  echo "Snapshot ready: ${SNAP_DIR}"
  echo "Latest pointer: ${dest}/latest -> snapshots/${SNAP_NAME}"
}

prune_snapshots() {
  local dest="$1"
  local keep="$2"
  [[ -n "$keep" ]] || return 0
  keep="$(printf '%s' "$keep" | tr -dc '0-9')"
  [[ -n "$keep" && "$keep" -ge 1 ]] || return 0
  mapfile -t snaps < <(ls -1dt "${dest}"/snapshots/* 2>/dev/null || true)
  local total="${#snaps[@]}"
  if (( total <= keep )); then
    echo "Retention: keeping all ${total} snapshot(s) (limit ${keep})."
    return 0
  fi
  local i
  for (( i = keep; i < total; i++ )); do
    echo "Pruning old snapshot: ${snaps[$i]}"
    rm -rf "${snaps[$i]}"
  done
}

rsync_incremental() {
  # rsync_incremental SRC_DIR DEST_FILES_DIR PREV_FILES_DIR_OR_EMPTY
  local src="$1"
  local dst="$2"
  local prev="${3:-}"
  mkdir -p "$dst"
  local -a args=(-aH --delete --info=stats2)
  if [[ -n "$prev" && -d "$prev" ]]; then
    args+=(--link-dest="$prev")
    echo "    Incremental vs: $prev"
  else
    echo "    Full copy (first snapshot or no previous files/)."
  fi
  rsync "${args[@]}" "${src}/" "${dst}/"
}

write_meta() {
  local snap="$1"
  local stack="$2"
  local note="$3"
  cat >"${snap}/META.txt" <<EOF
stack=${stack}
created=$(date -Iseconds)
host=$(hostname 2>/dev/null || echo unknown)
note=${note}
EOF
}




pull_pod_tree() {
  local pod="$1" remote="$2" dest="$3"
  mkdir -p "$dest"
  kubectl -n "$NS" exec "$pod" -- tar -C "$remote" -cf - . | tar -C "$dest" -xf -
}

push_pod_tree() {
  local pod="$1" remote="$2" src="$3"
  kubectl -n "$NS" exec "$pod" -- sh -c "rm -rf ${remote}/* ${remote}/.[!.]* ${remote}/..?* 2>/dev/null || true"
  tar -C "$src" -cf - . | kubectl -n "$NS" exec -i "$pod" -- tar -C "$remote" -xf -
}

do_backup() {
  need kubectl
  need_rsync
  [[ -n "$DEST" ]] || { echo "Provide --dest /path" >&2; exit 1; }
  DEST="$(mkdir -p "$DEST" && cd "$DEST" && pwd)"
  prepare_snapshot_dirs "$DEST"
  echo "==> Snapshot ${SNAP_NAME} -> ${SNAP_DIR}"
  local pod
  pod="$(kubectl -n "$NS" get pod -l app=heimdall -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  [[ -n "$pod" ]] || { echo "No Heimdall pod — is it installed?" >&2; exit 1; }

  local staging
  staging="$(mktemp -d)"
  echo "==> Archiving /config from ${pod}..."
  pull_pod_tree "$pod" /config "${staging}/files"
  local prev_files=""
  [[ -n "${PREV_LINK}" && -d "${PREV_LINK}/files" ]] && prev_files="${PREV_LINK}/files"
  rsync_incremental "${staging}/files" "${SNAP_DIR}/files" "${prev_files}"
  rm -rf "$staging"

  cp -a "${ROOT}/deploy.yaml" "${SNAP_DIR}/" 2>/dev/null || true
  kubectl -n "$NS" get deploy,svc,pvc -o yaml >"${SNAP_DIR}/resources.yaml" 2>/dev/null || true
  write_meta "${SNAP_DIR}" "$STACK_ID" "heimdall /config"
  finalize_snapshot "$DEST"
  prune_snapshots "$DEST" "${KEEP}"
  echo "Tip: store this backup root on an external drive or NAS."
}

do_restore() {
  need kubectl
  need_rsync
  [[ -n "$FROM" ]] || { echo "Provide --from /path" >&2; exit 1; }
  local snap
  snap="$(resolve_snapshot_dir "$FROM")"
  echo "Restoring from: $snap"
  [[ -d "${snap}/files" ]] || { echo "Missing files/" >&2; exit 1; }
  echo
  echo "Recommended: ./install.sh on the new cluster first, then restore."
  read -r -p "Type 'restore' to continue: " confirm || true
  [[ "${confirm}" == "restore" ]] || { echo "Aborted."; exit 1; }

  if ! kubectl -n "$NS" get deploy heimdall >/dev/null 2>&1; then
    echo "==> Deployment missing — applying deploy.yaml..."
    kubectl apply -f "${ROOT}/deploy.yaml"
    kubectl -n "$NS" rollout status deployment/heimdall --timeout=180s
  fi
  local pod
  pod="$(kubectl -n "$NS" get pod -l app=heimdall -o jsonpath='{.items[0].metadata.name}')"
  echo "==> Pushing /config into ${pod}..."
  push_pod_tree "$pod" /config "${snap}/files"
  kubectl -n "$NS" rollout restart deployment/heimdall
  kubectl -n "$NS" rollout status deployment/heimdall --timeout=180s
  echo "Restore finished from ${snap}."
}

case "${MODE}" in
  backup) do_backup ;;
  restore) do_restore ;;
  *) usage >&2; exit 1 ;;
esac
