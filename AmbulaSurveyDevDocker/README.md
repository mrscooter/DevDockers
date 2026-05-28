# AmbulaSurvey Dev Docker

Containerized full-stack dev environment for [AmbulaSurvey](https://github.com/ambula-survey). WebStorm + Python 3.12 + Node 20 + PostgreSQL 16 run inside Docker; you edit a bind-mounted host checkout. Modeled after [CLionDevDocker](../CLionDevDocker/).

The point is **filesystem isolation**: project tools (npm, uv, Playwright, AI agents, anything you install ad-hoc) run inside the container against the mounted code, with no risk of touching the host beyond your AmbulaSurvey checkout. Spin it up, work in it, throw it away, repeat.

## What's Inside

| Component | Details |
|-----------|---------|
| Base OS | Ubuntu 24.04 |
| IDE | WebStorm 2026.1.2 (X11-forwarded to host display) |
| Backend toolchain | Python 3.12 + `uv` (Astral) |
| Frontend toolchain | Node.js 20 + npm |
| Database | PostgreSQL 16 (sibling container, named volume for data) |
| Playwright | Chromium/Firefox/WebKit pre-baked at `/opt/ms-playwright`, version-matched to the project |
| Postgres client | `psql`, `pg_dump` (postgresql-client-16) |
| Shell | Zsh + Oh My Zsh (autosuggestions, syntax highlighting) + `keychain` (SSH agent) |
| AI assistant | Claude Code CLI (`claude` in PATH) |
| Editors | vim, nano, micro, `bat` (aliased from `batcat`) |
| Extras | git, make, Docker CLI (DinD via host socket), jq, tree, xclip |

**Explicitly NOT installed** (kept minimal): JDK (WebStorm ships its own JBR), CMake/Ninja/GCC, Conan, terminator, gnome-text-editor.

## Prerequisites

| Requirement | How to check / fix |
|---|---|
| Linux host with X11 | Wayland users need XWayland. Confirm with `echo $DISPLAY` (should print `:0` or similar). |
| Docker Engine + Compose v2 | `docker --version` and `docker compose version` should both succeed. |
| Your user in the `docker` group | `getent group docker` should list your username. If not: `sudo usermod -aG docker $USER && newgrp docker`, then re-login. |
| `xhost` available on host | `command -v xhost` (provided by `x11-xserver-utils` on Debian/Ubuntu; usually preinstalled on desktops). |
| ~6 GB free disk | Image is ~5.7 GB. |
| Outbound HTTPS | To `download.jetbrains.com`, `deb.nodesource.com`, `apt.postgresql.org`, `astral.sh`, `claude.ai`, `registry.npmjs.org`, ubuntu mirrors. |

Tested on Ubuntu 24.04 host.

## Two ways to provide AmbulaSurvey to the container

Pick one based on whether you want the project's files to also live on the host filesystem (outside the container).

### Mode A — Internal checkout (default, recommended)

You `git clone` the AmbulaSurvey repo **inside** the container, at `~/code/AmbulaSurvey`. The checkout lives in the named volume `ambula-dev-env-devuser-home` — invisible to the host, isolated from host tools, persists across container restarts, wiped only by `docker compose down -v`. This is the default; nothing in `.env` needs to change.

### Mode B — External bind-mount (opt-in)

You point `HOST_CODE_PATH` at an AmbulaSurvey checkout on the host, and it appears inside the container at `~/code/AmbulaSurvey-external` (note the `-external` suffix — distinct path so it never collides with a Mode A internal clone). The host copy and container view are the same files, two-way-sync, instantly. Useful if you want to edit with a host-side editor in parallel, or keep the checkout on your host backups.

To enable Mode B, uncomment **both** lines in `.env`:

```
COMPOSE_FILE=compose.yaml:compose.external-mount.yaml
HOST_CODE_PATH=/absolute/path/to/your/AmbulaSurvey/checkout
```

The two modes are not mutually exclusive — you can run with Mode B enabled and also have a separate Mode A clone at `~/code/AmbulaSurvey` if you ever want both.

## Setup (one-time)

### 1. Clone this dev-docker repo

```bash
mkdir -p ~/Tools/AmbulaSurveyDevDocker-workdir
cd ~/Tools/AmbulaSurveyDevDocker-workdir
git clone <this-repo-url> AmbulaSurveyDevDocker
cd AmbulaSurveyDevDocker
```

You do **not** need to clone AmbulaSurvey on the host. The default flow is to clone it inside the container later (see [Daily use → Clone AmbulaSurvey](#clone-ambulasurvey-inside-the-container)). The `-workdir` parent only matters if you choose to opt into the external host bind-mount mode (see [Two ways to provide AmbulaSurvey to the container](#two-ways-to-provide-ambulasurvey-to-the-container) below).

### 2. Configure `.env`

```bash
cp .env.example .env
```

Edit `.env`. At minimum, confirm:

| Variable | What |
|---|---|
| `DEV_NAME` / `DEV_EMAIL` | Used for `git config --global` inside the container, on every container start |
| `DOCKER_GID` | `getent group docker \| cut -d: -f3` on your host |

`USER_ID` / `GROUP_ID` default to `1000` — the typical first non-root Linux desktop user (`id -u` / `id -g`). This matters only for the optional external host bind-mount (keeps ownership consistent). If your host user is not UID 1000, override these to your actual IDs.

> The Dockerfile removes the `ubuntu:24.04` base image's built-in `ubuntu` user (which would otherwise occupy UID 1000) before creating `devuser`. That's why UID 1000 is usable as the default — unlike CLionDevDocker, which defaults to 1111.

See [`.env.example`](.env.example) for the full reference, including the opt-in external mount variables.

### 3. Allow Docker to talk to your X server

```bash
./xhost-setup.sh
```

Wraps `xhost +local:docker`. Must be run once per **host** session (after each login/reboot) before launching WebStorm.

### 4. Build the image

```bash
docker compose build
```

First build takes ~10-15 min (WebStorm tarball, Playwright browsers, apt layers). Subsequent rebuilds are incremental.

### 5. Start the services

```bash
docker compose up -d
```

Brings up:

- `ambula-dev-db` — PostgreSQL 16 (bound to host's `:5432`)
- `ambula-dev-container` — the dev environment (waits for Postgres to be healthy before starting)

Verify with `docker compose ps` — both should show `Up`, with `db` reporting `(healthy)`.

### 6. Smoke test (optional, recommended on first setup)

```bash
docker compose exec dev-env zsh -ic 'python3 --version && node --version && uv --version && webstorm --version | head -1 && psql --version'
docker compose exec dev-env zsh -ic 'ls /opt/ms-playwright/'
docker compose exec dev-env zsh -ic 'PGPASSWORD=devPass77 psql -h localhost -U admin -d ambula_survey -c "SELECT 1;"'
```

All three should succeed. If the third fails, the `db` container probably isn't healthy yet — wait a few seconds and retry.

## Daily use

### Get a shell

```bash
./zsh-into-docker-container.sh
# or: docker compose exec dev-env zsh
```

Open as many parallel shells as you need.

### Clone AmbulaSurvey (inside the container)

By default the container ships with no AmbulaSurvey checkout — clone it once and it lives in the named volume across container restarts:

```bash
mkdir -p ~/code && cd ~/code
git clone <ambula-survey-url> AmbulaSurvey      # HTTPS works without SSH setup
# or, after dropping SSH keys in ~/.ssh/:
git clone git@github.com:ambula-survey/ambula-survey.git AmbulaSurvey
```

(Skip this step if you've opted into external mounting — your host checkout shows up at `~/code/AmbulaSurvey-external` instead. See [Two ways to provide AmbulaSurvey](#two-ways-to-provide-ambulasurvey-to-the-container).)

### Launch WebStorm

From **inside** the container:

```bash
webstorm &
```

The window appears on your host display via X11 forwarding. On first launch, you'll need to activate your JetBrains license — settings and license persist in the named volume, so this is a one-time step.

Open `/home/devuser/code/AmbulaSurvey` (or `/home/devuser/code/AmbulaSurvey-external` if you opted into the host bind-mount).

### AmbulaSurvey one-time bootstrap (inside the container)

```bash
cd ~/code/AmbulaSurvey                                             # or AmbulaSurvey-external
uv sync                                                            # Python deps
(cd ambula-survey-frontend && npm ci && npx lefthook install)      # frontend + git hooks
make seed-dev-db                                                   # migrate + seed dev data
```

### Run the app (two shells inside the container)

```bash
make run-backend     # Django at :8000
make run-frontend    # Vite at :5173
```

Both are reachable from the host browser at `http://localhost:8000` and `http://localhost:5173` (containers use `network_mode: host` — no port mapping needed).

### Tests

```bash
cd ~/code/AmbulaSurvey
make test            # pytest + vitest
make preflight       # full CI suite locally (includes Playwright @smoke)
```

Playwright browsers are baked into the image, so e2e tests work immediately:

```bash
cd ~/code/AmbulaSurvey/ambula-survey-frontend
npx playwright test
```

### Database access

| | |
|--|--|
| Host | `localhost` (host network mode) |
| Port | `5432` |
| User | `admin` |
| Password | `devPass77` |
| Database | `ambula_survey` |

These match `AmbulaSurvey/CLAUDE.md`'s documented defaults, so no project-side configuration is needed.

```bash
# From inside the dev container:
PGPASSWORD=devPass77 psql -h localhost -U admin -d ambula_survey

# Or directly into the db container:
docker compose exec db psql -U admin -d ambula_survey
```

## Architecture

```
Host machine                              Docker (network_mode: host)
┌────────────────────────────┐            ┌──────────────────────────────────┐
│ /tmp/.X11-unix ────────────┼─ bind ─────┼─▶ /tmp/.X11-unix (GUI)           │
│ ~/.Xauthority ─────────────┼─ bind ─────┼─▶ ~/.Xauthority                  │
│ /var/run/docker.sock ──────┼─ bind ─────┼─▶ /var/run/docker.sock (DinD)    │
│                            │            │                                  │
│ AmbulaSurvey/ (opt-in B) ──┼─ bind ─────┼─▶ /home/devuser/code/            │
│   $HOST_CODE_PATH          │            │   AmbulaSurvey-external          │
│                            │            │                                  │
│                            │ named vol  │  /home/devuser   (dev-env)       │
│                            │ ◀──────────┼─  WebStorm settings, npm/uv      │
│                            │            │   caches, ~/.ssh, zsh history,   │
│                            │            │   AND code/AmbulaSurvey (Mode A) │
│                            │            │                                  │
│                            │ named vol  │  /var/lib/postgresql/data (db)   │
│                            │ ◀──────────┼─  Postgres data                  │
│                            │            │                                  │
│  localhost:5432 ◀──────────┼────────────┼──── postgres:16 sibling          │
│  localhost:8000            │            │     ▲ Django runserver           │
│  localhost:5173            │            │     ▲ Vite dev server            │
└────────────────────────────┘            └──────────────────────────────────┘
```

- **AmbulaSurvey checkout** lives in EITHER the named volume (Mode A — default) OR a host bind mount (Mode B — opt-in via `COMPOSE_FILE` switch in `.env`). See [Two ways to provide AmbulaSurvey](#two-ways-to-provide-ambulasurvey-to-the-container).
- **`/home/devuser` is a named volume** (`ambula-dev-env-devuser-home`) — IDE settings, license, caches, SSH keys, AND your in-container clone (Mode A) all survive container restarts. Wiped only by `docker compose down -v`.
- **Postgres data is its own named volume** (`ambula-pg-data`) — survives independently.
- **Host network mode** — both containers share the host's network stack. The dev-env container reaches Postgres at `localhost:5432`, matching AmbulaSurvey's documented default `DATABASE_URL`. No project-side config changes needed.

> **Named volume gotcha:** Docker only populates a named volume from the image on first creation. If you change `/home/devuser` content in the Dockerfile (e.g. new `.zshrc` plugins) and rebuild, the existing volume keeps the old content. Run `docker compose down -v` to wipe and let Docker re-populate from the new image.

## Docker-in-Docker

The dev container doesn't run its own Docker daemon. The host's `/var/run/docker.sock` is bind-mounted in, so any `docker` command inside the container executes on the **host's** Docker Engine — containers you start "from inside" are actually sibling containers on the host.

```bash
# Inside the dev container:
docker ps          # shows ALL host containers (including this one and the db)
```

The `DOCKER_GID` value in `.env` gives the container's `devuser` permission to talk to the host socket.

## Playwright

Browsers are baked into the image at `/opt/ms-playwright/` (system-wide, owned by `devuser`). `PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright` is exported globally. From inside the container:

```bash
cd ~/code/AmbulaSurvey/ambula-survey-frontend
npx playwright test                    # works immediately
npx playwright test --grep @smoke      # the 4 golden-path tests (used by preflight)
```

The image's baked version matches the `@playwright/test` pin in the project's `package.json` at build time. If the project upgrades to a different Playwright minor version, re-run `npx playwright install` inside the container — `devuser` owns `/opt/ms-playwright/` so no sudo is needed.

## Database lifecycle

```bash
# Stop everything (preserves data + IDE state)
docker compose down

# Stop and wipe EVERYTHING (Postgres data + IDE state + Playwright cache + SSH keys)
docker compose down -v

# Wipe ONLY the database, keep IDE state
docker compose down
docker volume rm ambulasurveydevdocker_ambula-pg-data
docker compose up -d
```

The Postgres container creates the user/db on first start from the env vars in `compose.yaml` (`POSTGRES_USER=admin`, `POSTGRES_PASSWORD=devPass77`, `POSTGRES_DB=ambula_survey`). Subsequent restarts use the volume's existing data; env-var changes only take effect after wiping the volume.

## SSH keys

Keys placed at `~/.ssh/id_*` inside the container are auto-loaded by `keychain` on each new zsh session (one passphrase prompt per container run). They persist in the home named volume.

**Generate fresh keys inside the container** (simplest):

```bash
ssh-keygen -t ed25519 -C "you@example.com"
cat ~/.ssh/id_ed25519.pub        # add to GitHub/GitLab
```

**Copy existing private keys from host:**

```bash
docker compose exec dev-env mkdir -p /home/devuser/.ssh
docker cp ~/.ssh/id_ed25519 ambula-dev-container:/home/devuser/.ssh/
docker compose exec dev-env sudo chown devuser:devgroup /home/devuser/.ssh/id_ed25519
```

> `docker cp` preserves the host file's UID/GID, which may not match `devuser`. Without the `chown`, SSH refuses to use the key.

**Or bind-mount your host `~/.ssh`** — add a `volumes:` entry to `compose.yaml` (avoids the ownership shuffle if host and container UIDs match, which they do by default).

## Git identity

`DEV_NAME` and `DEV_EMAIL` from `.env` are applied to `git config --global` on every container start by `entrypoint.sh`. To change them, edit `.env` and run `docker compose restart dev-env`. No rebuild or volume wipe needed.

## Running multiple instances

To work on different AmbulaSurvey branches in isolated containers simultaneously, clone this repo and use distinct compose project names:

```bash
cp -r ~/Tools/AmbulaSurveyDevDocker-workdir/AmbulaSurveyDevDocker \
      ~/Tools/AmbulaSurveyDevDocker-workdir/AmbulaSurveyDevDocker-branchB
# In branchB's .env, set unique values for:
#   HOST_CODE_PATH (different checkout)
#   CONTAINER_NAME=ambula-dev-container-branchB
#   DB_CONTAINER_NAME=ambula-dev-db-branchB
#   IMAGE_NAME=ambula-dev-env-branchB    # if the Dockerfiles differ
cd ~/Tools/AmbulaSurveyDevDocker-workdir/AmbulaSurveyDevDocker-branchB
docker compose -p ambula-branchB up -d --build
```

Each clone has its own `.env` (git-ignored) and named volumes.

> Note: `network_mode: host` means ports 5432/8000/5173 are global on the host. Two AmbulaSurvey instances can't both be up at the same time without port reassignment. Use one at a time, or adjust the project's `BACKEND_PORT`/`FRONTEND_PORT` per AmbulaSurvey's `worktree-add` recipe.

## Common operations

| Action | Command |
|--------|---------|
| Rebuild incrementally | `docker compose build` |
| Rebuild from scratch | `docker compose build --no-cache` |
| Status | `docker compose ps` |
| Live logs | `docker compose logs -f dev-env` / `docker compose logs -f db` |
| Stop, preserve state | `docker compose down` |
| Stop, wipe everything | `docker compose down -v` |
| Shell into dev-env | `./zsh-into-docker-container.sh` |
| Shell into postgres | `docker compose exec db psql -U admin -d ambula_survey` |

## Troubleshooting

| Problem | Solution |
|---------|----------|
| WebStorm window doesn't appear | Run `./xhost-setup.sh` on the host. Verify `echo $DISPLAY` inside the container matches the host's. |
| Permission denied on mounted code | Verify `USER_ID`/`GROUP_ID` in `.env` match `id -u`/`id -g` on the host, or `chown` the mounted dir to match. |
| Docker commands fail inside container | Confirm `DOCKER_GID` matches `getent group docker \| cut -d: -f3` on the host. |
| Volume mount fails on `up` | All required `.env` variables must be set. Validate with `docker compose config`. |
| Postgres "connection refused" | `docker compose ps` — `db` should be `running (healthy)`. If not: `docker compose logs db`. Common cause: host port 5432 already in use by another postgres. |
| Slow/glitchy GUI | Container uses software rendering (`LIBGL_ALWAYS_SOFTWARE=1`). For GPU passthrough, tweak `devices:` in `compose.yaml`. |
| Playwright "browser not found" | Verify `echo $PLAYWRIGHT_BROWSERS_PATH` is `/opt/ms-playwright` and `ls /opt/ms-playwright/` lists `chromium-*`, `firefox-*`, `webkit-*`. |

### X11 authorization error

If you forgot to run `./xhost-setup.sh`, WebStorm will fail with:

```
Authorization required, but no authorization protocol specified
java.awt.AWTError: Can't connect to X11 window server using ':0' as the value of the DISPLAY variable.
```

Fix: run `./xhost-setup.sh` on the **host** (not inside the container), then retry `webstorm &`. Required once per host session.
