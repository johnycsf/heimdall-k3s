# Breaking changes (read before updating)

**`git pull` / `git fetch` alone does not delete PersistentVolumes or restart pods.**  
Your cluster keeps serving the old Deployment until you re-run `install.sh` or `kubectl apply`.

If you installed from an **older revision**, re-applying current manifests is **not** an in-place upgrade. **Back up first.** Prefer **new PVCs** / a fresh namespace when moving to the current image.

## What changed

| Older clone | Current repo | Safe path |
|-------------|--------------|-----------|
| `lscr.io/linuxserver/heimdall` | `heimdall:local` (official `php:apache` build) | Keep the old Deployment **or** backup, delete PVC/namespace, reinstall |
| LinuxServer `/config` volume layout | New entrypoint `/config` layout | Do **not** reuse the old PVC with the new image |

## If you already have a working Heimdall

1. **Do nothing** — do not run `./install.sh` after pulling.
2. Or pin the last working commit.
3. Or migrate deliberately with a new PVC after backup.

`install.sh` refuses when it detects a LinuxServer Heimdall image still deployed, unless:

```bash
I_UNDERSTAND_THIS_IS_A_FRESH_INSTALL=yes ./install.sh
```
