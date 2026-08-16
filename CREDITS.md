# Credits

This repository packages and automates deployment. Credit for the applications belongs to their upstream developers.

## Heimdall

- **Heimdall Application Dashboard** — [linuxserver/Heimdall](https://github.com/linuxserver/Heimdall) and the Heimdall project ([heimdall.site](https://heimdall.site/))
- Built here on the official **PHP** Apache image ([Docker Official Images](https://hub.docker.com/_/php))
- **Kubernetes** — [kubernetes/kubernetes](https://github.com/kubernetes/kubernetes)

## Shared johnycsf tooling

These install/manage/backup helpers are used across johnycsf stacks. Credit the upstream projects:

| Tool | Role in this repo | Upstream |
|------|-------------------|----------|
| **age** | Optional encrypted offsite backup exports (`./manage.sh backup --encrypt` / password-protected tar archives) | [FiloSottile/age](https://github.com/FiloSottile/age) |
| **zip** / **unzip** | Optional compressed zip exports (`./manage.sh backup --archive zip`) | [Info-ZIP](http://www.info-zip.org/) |
| **xz** | Optional tar.xz compressed exports | OS `xz` / xz-utils package |
| **rsync** | Incremental hardlink snapshot backups | [rsync.samba.org](https://rsync.samba.org/) / your OS package |
| **Docker** / **Docker Compose** | Container runtime for app stacks | [docker.com](https://www.docker.com/) |
| **Catppuccin** | Color inspiration for the pastel terminal UI | [catppuccin/catppuccin](https://github.com/catppuccin/catppuccin) |

When you add a new helper tool or feature dependency, **add it here** (and in `repo-framework`’s template) in the same PR.

All trademarks and project names belong to their respective owners. This repo is not affiliated with or endorsed by the Heimdall, LinuxServer, or Kubernetes teams.
