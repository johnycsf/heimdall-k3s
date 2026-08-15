# heimdall-k8s

![Repobeats analytics image](https://repobeats.axiom.co/api/embed/bc9a5953ce99f544324924618df9438258cb6ec2.svg "Repobeats analytics image")

Deploy [Heimdall](https://heimdall.site/) on a [Kubernetes](https://kubernetes.io/) homelab with almost no Kubernetes knowledge.

Docker Compose version (no Kubernetes needed): [heimdall-docker](https://github.com/johnycsf/heimdall-docker)

Heimdall is a simple application dashboard — a start page for links to the rest of your self-hosted apps (Nextcloud, Vaultwarden, etc.).

Uses the **official** [`php:8.4-apache`](https://hub.docker.com/_/php) image and builds Heimdall from the [upstream release](https://github.com/linuxserver/Heimdall/releases) via the `Dockerfile` in this repo (no LinuxServer container runtime).

`install.sh` builds `heimdall:local` and loads it into k3s/kind when those tools are present.

> **Updating an older clone?** Pulling git is safe. Re-running `./install.sh` against a LinuxServer Deployment is not. Read [BREAKING-CHANGES.md](BREAKING-CHANGES.md).

## What you need

1. A working **Kubernetes** cluster (`kubectl` talks to it)
2. **docker** or **podman** (to build the image)
3. **Longhorn** storage (or change `storageClassName` in `deploy.yaml`)
4. `helm` only if you still need to install Longhorn

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

Only for clusters already on `heimdall:local` from this repo:

```bash
./install.sh
```

LinuxServer-based installs: see [BREAKING-CHANGES.md](BREAKING-CHANGES.md) — do not re-run install after pull unless you intend a fresh install.

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
