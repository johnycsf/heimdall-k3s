# heimdall-k8s

Deploy [Heimdall](https://heimdall.site/) on a [Kubernetes](https://kubernetes.io/) homelab with almost no Kubernetes knowledge.

Heimdall is a simple application dashboard — a start page for links to the rest of your self-hosted apps (Nextcloud, Vaultwarden, etc.).

This repo follows the current [LinuxServer Heimdall image docs](https://docs.linuxserver.io/images/docker-heimdall/).

## What you need

1. A working **Kubernetes** cluster (`kubectl` talks to it)
2. **Longhorn** storage (or change `storageClassName` in `deploy.yaml`)
3. `helm` only if you still need to install Longhorn

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

Or apply the manifests yourself:

```bash
kubectl apply -f deploy.yaml
kubectl -n heimdall get svc heimdall
```

## Open the dashboard

```bash
kubectl -n heimdall get svc heimdall
```

Use the `EXTERNAL-IP` (or your node IP with k3s ServiceLB / MetalLB):

- **HTTP:** `http://EXTERNAL-IP/`
- **HTTPS:** `https://EXTERNAL-IP/` (self-signed certificate — your browser will warn)

## Customize

Edit `deploy.yaml` before installing (or re-apply after editing):

| Setting | Where | Notes |
|--------|--------|--------|
| Timezone | `TZ` | Default `America/New_York` |
| User/group | `PUID` / `PGID` | Default `1000` (LinuxServer recommendation) |
| LAN app links | `ALLOW_INTERNAL_REQUESTS` | Set `true` so Heimdall can reach private IPs |
| Disk size | PVC `storage` | Default `1Gi` |

## Update

```bash
kubectl -n heimdall set image deployment/heimdall \
  heimdall=lscr.io/linuxserver/heimdall:latest
kubectl -n heimdall rollout status deployment/heimdall
```

## Uninstall

```bash
kubectl delete -f deploy.yaml
```

This also deletes the PVC and the Longhorn volume data.

## Notes for beginners

- One replica only — Heimdall config is not meant to be shared across many pods.
- `image: ...:latest` tracks stable LinuxServer releases. Pin a version tag if you want stricter control.
- Put Heimdall behind a reverse proxy (Traefik, nginx, Caddy) if you expose it outside your LAN.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
