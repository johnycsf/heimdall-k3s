# heimdall-k8s

Deploy [Heimdall](https://heimdall.site/) on a [Kubernetes](https://kubernetes.io/) homelab with almost no Kubernetes knowledge.

Docker Compose version (no Kubernetes needed): [heimdall-docker](https://github.com/johnycsf/heimdall-docker)

Heimdall is a simple application dashboard — a start page for links to the rest of your self-hosted apps (Nextcloud, Vaultwarden, etc.).

Uses the **official** [`php:8.4-apache`](https://hub.docker.com/_/php) image and builds Heimdall from the [upstream release](https://github.com/linuxserver/Heimdall/releases). Published as `ghcr.io/johnycsf/heimdall:latest` (no LinuxServer container runtime).

After the first GitHub Actions build, open the [heimdall package](https://github.com/users/johnycsf/packages/container/package/heimdall) → **Package settings** → set visibility to **Public** (required once so clusters can pull without a GitHub login).

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

```bash
kubectl -n heimdall rollout restart deployment/heimdall
kubectl -n heimdall rollout status deployment/heimdall
```

## Uninstall

```bash
kubectl delete -f deploy.yaml
```

This also deletes the PVC and the Longhorn volume data.

## Notes for beginners

- One replica only — Heimdall config is not meant to be shared across many pods.
- The image is rebuilt from upstream Heimdall releases on `php:apache`. Pin a digest if you want stricter control.
- Put Heimdall behind a reverse proxy (Traefik, nginx, Caddy) if you expose it outside your LAN.
- Fresh install only — do not reuse a LinuxServer `/config` volume with this image.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
