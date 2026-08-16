# heimdall-k8s

![Repobeats analytics image](https://repobeats.axiom.co/api/embed/bc9a5953ce99f544324924618df9438258cb6ec2.svg "Repobeats analytics image")

Deploy [Heimdall](https://heimdall.site/) on a [Kubernetes](https://kubernetes.io/) homelab with almost no Kubernetes knowledge.

Docker Compose version (no Kubernetes needed): [heimdall-docker](https://github.com/johnycsf/heimdall-docker)

Heimdall is a simple application dashboard — a start page for links to the rest of your self-hosted apps (Nextcloud, Vaultwarden, etc.).

Uses the **official** [`php:8.4-apache`](https://hub.docker.com/_/php) image and builds Heimdall from the [upstream release](https://github.com/linuxserver/Heimdall/releases) via the `Dockerfile` in this repo (no LinuxServer container runtime).

`install.sh` builds `heimdall:local` and loads it into k3s/kind when those tools are present.

> **Updating an older clone?** Pulling git is safe. Re-running `./install.sh` against a LinuxServer Deployment is not. Read [BREAKING-CHANGES.md](BREAKING-CHANGES.md).

## What you need

- A Kubernetes cluster (`kubectl` context already set)
- `sudo` on this machine so `./install.sh` can install missing tools (kubectl, helm, curl, openssl, rsync, …)
- Disk for PersistentVolumes

`./install.sh` detects your OS, installs host dependencies, and **asks which StorageClass to use** (Longhorn, cluster default, local-path, or any class already in the cluster). Longhorn can be installed for you if you pick it. Non-interactive: `STORAGE_CLASS=longhorn ./install.sh`.


## One-time: install Longhorn

```bash
helm repo add longhorn https://charts.longhorn.io
helm repo update
helm install longhorn longhorn/longhorn \
  --namespace longhorn-system --create-namespace

kubectl -n longhorn-system get pod
```

Wait until the Longhorn pods are `Running` / `Ready`.  
Longhorn will **automatically** create the Heimdall volume from the PVC — you do not need to create volumes by hand in the Longhorn UI.

## Install Heimdall

```bash
git clone https://github.com/johnycsf/heimdall-k8s.git
cd heimdall-k8s
chmod +x install.sh
./install.sh
```

## Open the dashboard

```bash
kubectl -n heimdall get svc heimdall
```

Use the `EXTERNAL-IP` (or your node IP with k3s ServiceLB / MetalLB):

- **HTTP:** `http://EXTERNAL-IP/`

Set `APP_URL` in `deploy.yaml` to that same URL after you know it, then re-apply.

## Customize

Edit `deploy.yaml` before installing (or re-apply after editing):

| Setting | Where | Notes |
|--------|--------|--------|
| Timezone | `TZ` | Default `America/New_York` |
| LAN app links | `ALLOW_INTERNAL_REQUESTS` | Set `true` so Heimdall can reach private IPs |
| Public URL | `APP_URL` | Match the URL you open in the browser |
| Disk size | PVC `storage` | Default `1Gi` |

## Update

Keep the stack current (safe while pods are running; brief rollout downtime):

```bash
chmod +x update.sh
./update.sh
```

Before changing anything, the script runs `./backup.sh` into `./backups` (incremental, database-safe). After a successful update it asks whether to **keep** or **delete** that snapshot, and how many local copies to retain (older ones are pruned). Copy important backups to an external drive, NAS, or cloud so they do not fill this disk.

To roll back later (same tool as disaster recovery):

```bash
./backup.sh --restore --from ./backups
# or from an external copy:
./backup.sh --restore --from /mnt/usb/my-backups
```

Older `backups/update-*` tarball folders (from previous script versions) are no longer used by `./update.sh`; use each folder's `RESTORE.txt` if you still need one, or delete them to free space.

This re-applies manifests, rolls Deployments so `:latest` images refresh, and prunes **unused** images on this machine when possible (k3s `crictl rmi --prune` or Docker dangling prune). PVCs and Secrets are left untouched.

Only for clusters already on `heimdall:local` — see [BREAKING-CHANGES.md](BREAKING-CHANGES.md).


## Disaster recovery (full backup / restore)

Incremental snapshots via `rsync` hardlinks (unchanged files are not re-copied). `./update.sh` uses this same `backup.sh` before updating (into `./backups`).

```bash
chmod +x backup.sh

# Backup to USB/NAS/external path (repeat anytime; later runs are incremental)
./backup.sh --dest /mnt/usb/heimdall-k8s-backups
./backup.sh --dest /mnt/usb/heimdall-k8s-backups --keep 5   # optional: retain only newest N

# On a brand-new machine/cluster after ./install.sh:
./backup.sh --restore --from /mnt/usb/heimdall-k8s-backups
# or a specific snapshot:
./backup.sh --restore --from /mnt/usb/heimdall-k8s-backups/snapshots/YYYYMMDD-HHMMSS
```

Each snapshot includes `SHA256SUMS` plus a `snapshot_sha256` key in `META.txt`. Restore verifies these and **warns** (does not abort) if integrity is lost.

Keep the backup root on **one filesystem** so hardlinks work. Prefer an external drive, NAS, or cloud sync of that folder.

**Database safety:** Nextcloud uses a verified MariaDB *logical* dump (`mariadb-dump --single-transaction`) — the live `data/db` / DB PVC files are never rsync'd. SQLite apps (Heimdall, Vaultwarden) are stopped or scaled to 0, WAL-checkpointed when `sqlite3` is available, integrity-checked, then copied. Incremental hardlinks apply to file trees; each SQL dump is a full verified file with a SHA-256 in `META.txt`.


## Uninstall

```bash
kubectl delete -f deploy.yaml
```

This also deletes the PVC and the Longhorn volume data.

## Notes for beginners

- One replica only — Heimdall config is not meant to be shared across many pods.
- Fresh install only — do not reuse a LinuxServer `/config` volume with this image.
- Multi-node clusters: push `heimdall:local` to a registry you control and update `image` / `imagePullPolicy` in `deploy.yaml`.
- Put Heimdall behind a reverse proxy (Traefik, nginx, Caddy) if you expose it outside your LAN.


## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
