# Full-Stack Web Dev Docker

Containerized full-stack web dev environment: WebStorm + Python 3.12 + Node 20 +
Playwright run inside Docker, talking to a shared PostgreSQL 16. Nothing about it
is tied to a specific project - it serves any Python-backend + Node-frontend +
Postgres stack (Django + React, FastAPI + Vue, Flask + Svelte, ...). The image
ships runtimes and tooling; your app's own dependencies arrive when you run
`uv sync` / `npm ci` against its lockfiles. Modeled after
[CLionDevDocker](../CLionDevDocker/) (the C++ sibling).

The point is **filesystem isolation**: project tools (npm, uv, Playwright, AI
agents, anything you install ad-hoc) run inside the container, with no risk of
touching the host beyond your project checkout. Spin it up, work in it, throw it
away, repeat.

## What's Inside

| Component | Details |
|-----------|---------|
| Base OS | Ubuntu 24.04 |
| IDE | WebStorm 2026.1.2 (X11-forwarded to host display) |
| Backend toolchain | Python 3.12 + `uv` (Astral) |
| Frontend toolchain | Node.js 20 + npm |
| Database | Shared PostgreSQL 16 in a separate project ([../shared-db](../shared-db/)) |
| Playwright | Chromium/Firefox/WebKit pre-baked at `/opt/ms-playwright` |
| Postgres client | `psql`, `pg_dump` (postgresql-client-16) |
| Shell | Zsh + Oh My Zsh (autosuggestions, syntax highlighting) + `keychain` (SSH agent) |
| AI assistant | Claude Code CLI (`claude` in PATH) |
| Editors | vim, nano, micro, `bat` (aliased from `batcat`) |
| Extras | git, make, Docker CLI (DinD via host socket), jq, tree, xclip |

**Explicitly NOT installed** (kept minimal): JDK (WebStorm ships its own JBR),
CMake/Ninja/GCC, Conan, terminator, gnome-text-editor.

## Prerequisites

| Requirement | How to check / fix |
|---|---|
| Linux host with X11 | Wayland users need XWayland. Confirm with `echo $DISPLAY` (should print `:0` or similar). |
| Docker Engine + Compose v2 | `docker --version` and `docker compose version` should both succeed. |
| Your user in the `docker` group | `getent group docker` should list your username. If not: `sudo usermod -aG docker $USER && newgrp docker`, then re-login. |
| `xhost` available on host | `command -v xhost` (provided by `x11-xserver-utils` on Debian/Ubuntu). |
| ~6 GB free disk | Image is ~5.7 GB. |
| Outbound HTTPS | To `download.jetbrains.com`, `deb.nodesource.com`, `apt.postgresql.org`, `astral.sh`, `claude.ai`, `registry.npmjs.org`, ubuntu mirrors. |

Tested on Ubuntu 24.04 host.

## Architecture at a glance

The database is **not** inside this compose project. It runs once as a separate
shared service ([../shared-db](../shared-db/)), and every dev-docker - including
multiple worktrees running at the same time - connects to it over the host at
`localhost:5433`. The dev-docker uses **host networking**, so any dev server you
launch is reachable on the host at the same port with no mapping.

```
                  shared-db project (start once)
                  Postgres on 127.0.0.1:5433
                            |  localhost:5433
        ┌───────────────────┼────────────────────┐
   dev-docker A         dev-docker B          dev-docker C     (worktrees)
   Django :8000         Django :8012          Django :8013
   Vite   :5173         Vite   :5205          Vite   :5206
   db: app_a            db: app_b             db: app_c        (own DB, same server)

   each dev-docker (host networking):
     /home/devuser           <- named volume (IDE settings/license, caches, ~/.ssh,
                                 zsh history, AND the Mode A in-container checkout)
     DATABASE_URL, PG*        <- exported, point at localhost:5433/<its db>
     X11 socket, docker.sock  <- bind-mounted from host (GUI + DinD)
```

- **`/home/devuser` is a named volume** (`devuser-home`) - IDE settings, license,
  caches, SSH keys, AND your in-container clone (Mode A) survive container
  restarts. Wiped only by `docker compose down -v`.
- **Host network mode** - the container shares the host's network stack, so it
  reaches the shared Postgres at `localhost:5433` and serves the app on the host
  directly.

> **Named volume gotcha:** Docker only populates a named volume from the image on
> first creation. If you change `/home/devuser` content in the Dockerfile (e.g.
> new `.zshrc` plugins) and rebuild, the existing volume keeps the old content.
> Run `docker compose down -v` to wipe and let Docker re-populate.

## Two ways to provide your project to the container

Pick one based on whether you want the project's files to also live on the host
filesystem (outside the container).

### Mode A - Internal checkout (default, recommended)

You `git clone` your project **inside** the container, at `~/code/<project>`. The
checkout lives in the named volume `devuser-home` - invisible to the host,
isolated from host tools, persists across container restarts, wiped only by
`docker compose down -v`. This is the default; nothing in `.env` needs to change.

### Mode B - External bind-mount (opt-in)

You point `HOST_CODE_PATH` at a checkout on the host, and it appears inside the
container at `~/code/project-external` (the `-external` suffix means it never
collides with a Mode A clone). Host copy and container view are the same files,
two-way-sync. Useful if you want to edit with a host-side editor in parallel or
keep the checkout on host backups.

To enable Mode B, uncomment **both** lines in `.env`:

```
COMPOSE_FILE=compose.yaml:compose.external-mount.yaml
HOST_CODE_PATH=/absolute/path/to/your/project
```

The two modes are not mutually exclusive.

## Setup (one-time)

### 1. Start the shared database (once for all worktrees)

```bash
cd ../shared-db
cp .env.example .env          # adjust only if you want non-default creds/port
docker compose up -d
docker compose ps             # postgres should be Up (healthy)
```

See [../shared-db/README.md](../shared-db/README.md). Skip if it is already running.

### 2. Configure this dev-docker's `.env`

```bash
cd ../FullStackWebDevDocker
cp .env.example .env
```

Edit `.env`. At minimum:

| Variable | What |
|---|---|
| `DEV_NAME` / `DEV_EMAIL` | `git config --global` inside the container, on every start |
| `DOCKER_GID` | `getent group docker \| cut -d: -f3` on your host |
| `POSTGRES_USER` / `POSTGRES_PASSWORD` / `PG_HOST_PORT` | **must match** `../shared-db/.env` |
| `POSTGRES_DB` | this worktree's database name on the shared server |

`USER_ID` / `GROUP_ID` default to `1000` (the typical first non-root Linux user,
`id -u` / `id -g`). This matters only for the optional Mode B bind-mount, to keep
host file ownership correct. See [`.env.example`](.env.example) for the full
reference.

### 3. Allow Docker to talk to your X server

```bash
./xhost-setup.sh
```

Wraps `xhost +local:docker`. Run once per **host** session (after each login)
before launching WebStorm.

### 4. Build and start

```bash
docker compose build      # first build ~10-15 min (WebStorm, Playwright, apt)
docker compose up -d
docker compose ps         # dev-env should be Up
```

### 5. Smoke test (optional)

```bash
docker compose exec dev-env zsh -ic 'python3 --version && node --version && uv --version && webstorm --version | head -1 && psql --version'
docker compose exec dev-env zsh -ic 'ls /opt/ms-playwright/'
docker compose exec dev-env zsh -ic 'echo $DATABASE_URL && psql -c "SELECT 1;"'
```

The last line confirms the container can reach the shared DB (start `../shared-db`
first, and create this worktree's database - see below - if `psql` reports it is
missing).

## Daily use

### Get a shell

```bash
./zsh-into-docker-container.sh
# or: docker compose exec dev-env zsh
```

### Clone your project (Mode A, inside the container)

```bash
mkdir -p ~/code && cd ~/code
git clone <your-project-url> <project>          # HTTPS works without SSH setup
```

(Skip if you opted into Mode B - your host checkout is at `~/code/project-external`.)

### Launch WebStorm

From **inside** the container:

```bash
webstorm &
```

The window appears on your host display via X11 forwarding. On first launch,
activate your JetBrains license - it persists in the named volume, so this is a
one-time step. Open `~/code/<project>` (or `~/code/project-external`).

### Run the app

Launch your backend and frontend dev servers on whatever ports this worktree
uses. With host networking they are reachable from the host browser at the same
port with no mapping, e.g. `http://localhost:8000` and `http://localhost:5173`.

> When running multiple worktrees at once, give each worktree distinct ports
> (worktree A on 8000/5173, worktree B on 8012/5205, ...) so they don't collide
> on the host. The dev-docker imposes no port policy - the port is whatever your
> server binds.

## Database connection

Postgres runs in [../shared-db](../shared-db/) and is reachable from inside the
container at `localhost:5433`. The connection is pre-wired as environment
variables (see `compose.yaml`), all derived from this worktree's `.env`:

```bash
echo $DATABASE_URL        # postgresql://admin:devPass77@localhost:5433/<your_db>
echo $PGHOST:$PGPORT      # localhost:5433
psql                      # bare - uses the standard PG* vars, no flags needed
```

### Create this worktree's database (once)

The shared server hosts one database per worktree. Create yours against the
running shared DB:

```bash
createdb <your_db>        # inside the container; PG* vars are already set
# (equivalently, from the host: createdb -h localhost -p 5433 -U admin <your_db>)
```

Set `POSTGRES_DB=<your_db>` in this dev-docker's `.env` so `DATABASE_URL`/`PGDATABASE`
point at it.

### Wire your app to it (Django shown; adapt for other frameworks)

**Recommended - read the exported `DATABASE_URL`:**

```python
# settings.py  (needs `dj-database-url` in your deps)
import os, dj_database_url
DATABASES = {"default": dj_database_url.config(default=os.environ["DATABASE_URL"])}
```

**Or configure explicitly** (matches the exported `PG*` vars):

```python
DATABASES = {"default": {
    "ENGINE": "django.db.backends.postgresql",
    "NAME": os.environ["PGDATABASE"],
    "USER": os.environ["PGUSER"],
    "PASSWORD": os.environ["PGPASSWORD"],
    "HOST": os.environ["PGHOST"],     # localhost
    "PORT": os.environ["PGPORT"],     # 5433
}}
```

Non-Django backends: read `DATABASE_URL`, or build the DSN from the `PG*` vars.
Most Postgres libraries (psycopg, asyncpg via libpq) also auto-read the `PG*`
vars when given no explicit connection arguments.

### Direct access

```bash
psql                                              # inside the container
docker compose -f ../shared-db/compose.yaml exec postgres psql -U admin -d <your_db>
```

## Docker-in-Docker

The dev container has no daemon of its own. The host's `/var/run/docker.sock` is
bind-mounted in, so `docker` commands inside execute on the **host's** engine -
containers you start "from inside" are sibling containers on the host.

```bash
docker ps          # inside the container: shows ALL host containers
```

`DOCKER_GID` in `.env` gives the container's `devuser` permission on the socket.

## Playwright

Browsers are baked at `/opt/ms-playwright/` (system-wide, owned by `devuser`),
and `PLAYWRIGHT_BROWSERS_PATH` is exported globally, so e2e tests work immediately:

```bash
cd ~/code/<project>/<frontend-dir>
npx playwright test
```

The baked version is pinned in the Dockerfile. If your project pins a different
Playwright minor version, re-run `npx playwright install` inside the container -
`devuser` owns `/opt/ms-playwright/`, so no sudo is needed.

## SSH keys

Keys placed at `~/.ssh/id_*` inside the container are auto-loaded by `keychain` on
each new zsh session (one passphrase prompt per container run). They persist in
the home named volume.

```bash
ssh-keygen -t ed25519 -C "you@example.com"
cat ~/.ssh/id_ed25519.pub        # add to GitHub/GitLab
```

To copy an existing key from the host: `docker cp ~/.ssh/id_ed25519
<container>:/home/devuser/.ssh/` then `chown` it to `devuser` (docker cp keeps the
host UID).

## Git identity

`DEV_NAME` / `DEV_EMAIL` from `.env` are applied to `git config --global` on every
container start by `entrypoint.sh`. Change them in `.env` and run
`docker compose restart dev-env` - no rebuild or volume wipe needed.

## Running multiple worktrees

To work on several worktrees of your project at once, each in its own dev-docker,
all sharing the one `../shared-db`:

```bash
cp -r FullStackWebDevDocker FullStackWebDevDocker-wtB
# in -wtB/.env:
#   POSTGRES_DB=app_b                          # its own database on the shared server
#   CONTAINER_NAME=fullstack-web-dev-wtB       # unique container name
#   IMAGE_NAME=fullstack-web-dev-env           # share the image (same build)
cd FullStackWebDevDocker-wtB
docker compose -p fswdd-wtB up -d
```

Each copy has its own `.env` (git-ignored) and its own `devuser-home` volume
(prefixed by the compose project name). They share the one shared Postgres, each
using its own database. Give each worktree's dev servers **distinct ports** -
host networking means 8000/5173/etc. are global on the host, so two worktrees on
the same port collide.

## Common operations

| Action | Command |
|--------|---------|
| Rebuild incrementally | `docker compose build` |
| Rebuild from scratch | `docker compose build --no-cache` |
| Status | `docker compose ps` |
| Live logs | `docker compose logs -f dev-env` |
| Stop, preserve state | `docker compose down` |
| Stop, wipe this dev-docker's state | `docker compose down -v` (does NOT touch the shared DB) |
| Shell into dev-env | `./zsh-into-docker-container.sh` |
| Shared DB shell | `docker compose -f ../shared-db/compose.yaml exec postgres psql -U admin` |

## Troubleshooting

| Problem | Solution |
|---------|----------|
| WebStorm window doesn't appear | Run `./xhost-setup.sh` on the host. Verify `echo $DISPLAY` inside the container matches the host's. |
| `psql` / app can't reach the DB | Is `../shared-db` up and healthy? Do `POSTGRES_USER`/`POSTGRES_PASSWORD`/`PG_HOST_PORT` match `../shared-db/.env`? Does this worktree's database exist (`createdb`)? |
| Permission denied on Mode B mounted code | Verify `USER_ID`/`GROUP_ID` in `.env` match `id -u`/`id -g` on the host. |
| Docker commands fail inside container | Confirm `DOCKER_GID` matches `getent group docker \| cut -d: -f3` on the host. |
| Volume mount / startup fails | All required `.env` variables must be set. Validate with `docker compose config`. |
| Slow/glitchy GUI | Software rendering (`LIBGL_ALWAYS_SOFTWARE=1`). For GPU passthrough, tweak `devices:` in `compose.yaml`. |
| Playwright "browser not found" | Verify `echo $PLAYWRIGHT_BROWSERS_PATH` is `/opt/ms-playwright` and `ls` it lists the browsers. |

### X11 authorization error

If you forgot `./xhost-setup.sh`, WebStorm fails with:

```
Authorization required, but no authorization protocol specified
java.awt.AWTError: Can't connect to X11 window server using ':0' as the value of the DISPLAY variable.
```

Fix: run `./xhost-setup.sh` on the **host** (not inside the container), then retry
`webstorm &`. Required once per host session.
