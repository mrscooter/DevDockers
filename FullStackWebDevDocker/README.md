# Full-Stack Web Dev Docker

A throwaway, containerized dev environment for **any** full-stack web project -
Python backend + Node frontend + PostgreSQL (Django + React, FastAPI + Vue,
Flask + Svelte, ...). It bundles the IDE and all the runtimes/tooling so your
work - including AI agents you let loose inside - stays isolated from the host:
the only host files touched are your project checkout (and only if you opt in).

The image ships runtimes, not your app. Your project's own dependencies arrive
when you run `uv sync` / `npm ci` against its lockfiles inside the container.

**The database lives outside this project.** Postgres runs once as a separate
shared service ([../shared-db](../shared-db/)); every dev-docker - including
several worktrees at once - connects to it at `localhost:5433`. That is what lets
you run multiple worktrees simultaneously without database port clashes.

```
                  shared-db (start once)  -  Postgres on 127.0.0.1:5433
                            |  localhost:5433
        ┌───────────────────┼────────────────────┐
   dev-docker A         dev-docker B          dev-docker C     (worktrees)
   own ports            own ports             own ports
   db: app_a            db: app_b             db: app_c        (own DB, one server)
```

| Inside the image | |
|---|---|
| OS / IDE | Ubuntu 24.04, WebStorm 2026.1.2 (GUI via X11 to your host) |
| Backend | Python 3.12 + `uv` (Astral) |
| Frontend | Node.js 20 + npm, Playwright browsers pre-baked |
| DB client | `psql` / `pg_dump` (postgresql-client-16) |
| Shell / tools | zsh + Oh My Zsh + keychain, Claude Code CLI, git, Docker CLI, vim/nano/micro/bat, jq, tree, xclip |

---

## Setup from scratch

Run these in order. Steps 0-5 are on the **host**; from step 6 you are **inside
the container**. Host-side commands assume you start in this directory
(`FullStackWebDevDocker/`).

### 0. Check prerequisites (host)

| Need | Check |
|---|---|
| Docker Engine + Compose v2 | `docker --version && docker compose version` |
| You are in the `docker` group | `getent group docker` lists you; else `sudo usermod -aG docker $USER && newgrp docker` |
| X11 (for the WebStorm GUI) | `echo $DISPLAY` prints `:0` or similar (Wayland: needs XWayland) |
| `xhost` present | `command -v xhost` |
| ~6 GB free disk | image is ~5.7 GB |

### 1. Start the shared database (once for all worktrees)

```bash
cd ../shared-db
cp .env.example .env          # adjust only if you want non-default creds/port
docker compose up -d
docker compose ps             # postgres should be Up (healthy)
cd ../FullStackWebDevDocker
```

Skip if it is already running. Details: [../shared-db/README.md](../shared-db/README.md).

### 2. Configure this dev-docker's `.env`

```bash
cp .env.example .env
```

Edit `.env` and set (the file documents every variable):

| Variable | Value |
|---|---|
| `DEV_NAME` / `DEV_EMAIL` | your git identity (used inside the container) |
| `DOCKER_GID` | output of `getent group docker \| cut -d: -f3` |
| `POSTGRES_USER` / `POSTGRES_PASSWORD` / `PG_HOST_PORT` | **must match `../shared-db/.env`** |
| `POSTGRES_DB` | this worktree's database name (e.g. `app_dev`) |

Defaults for everything else are fine on a typical UID-1000 Linux desktop.
Validate with `docker compose config` if unsure.

### 3. Allow Docker to reach your X server (host, once per login)

```bash
./xhost-setup.sh
```

### 4. Build the image

```bash
docker compose build          # first build ~10-15 min (WebStorm, Playwright, apt)
```

### 5. Start the container

```bash
docker compose up -d
docker compose ps             # dev-env should be Up
```

### 6. Get a shell inside

```bash
./zsh-into-docker-container.sh
```

Everything below runs inside the container.

### 7. Get your project into the container

Default (Mode A) - clone it inside; lives in the container's named volume:

```bash
mkdir -p ~/code && cd ~/code
git clone <your-project-url> <project>
```

(Alternative Mode B mounts a host checkout instead - see
[Providing your project](#providing-your-project-mode-a-vs-mode-b).)

### 8. Create this worktree's database

The shared server hosts one database per worktree; create yours (the `PG*` env
vars are already set, so no flags needed):

```bash
createdb $PGDATABASE
```

### 9. Install project deps and wire up the DB

```bash
cd ~/code/<project>
uv sync                                   # backend deps
( cd <frontend-dir> && npm ci )           # frontend deps
```

Point your app at the database using the pre-exported `DATABASE_URL` / `PG*`
vars - see [Database connection](#database-connection).

### 10. Run it

```bash
webstorm &                                # IDE window opens on your host display
# launch your backend + frontend dev servers on this worktree's ports;
# with host networking they are reachable from the host browser at the same port.
```

First WebStorm launch: activate your JetBrains license once (it persists in the
named volume).

That is the whole setup. The sections below are reference.

---

## Database connection

Postgres runs in [../shared-db](../shared-db/), reachable inside the container at
`localhost:5433`. The connection is pre-exported as environment variables (from
your `.env`):

```bash
echo $DATABASE_URL        # postgresql://admin:devPass77@localhost:5433/<your_db>
echo $PGHOST:$PGPORT      # localhost:5433
psql                      # bare - uses the standard PG* vars, no flags
```

Wire your app to it. **Django via `DATABASE_URL`** (recommended):

```python
# settings.py  (needs `dj-database-url`)
import os, dj_database_url
DATABASES = {"default": dj_database_url.config(default=os.environ["DATABASE_URL"])}
```

Or explicitly, from the `PG*` vars:

```python
DATABASES = {"default": {
    "ENGINE": "django.db.backends.postgresql",
    "NAME": os.environ["PGDATABASE"], "USER": os.environ["PGUSER"],
    "PASSWORD": os.environ["PGPASSWORD"],
    "HOST": os.environ["PGHOST"], "PORT": os.environ["PGPORT"],
}}
```

Other frameworks: read `DATABASE_URL`, or rely on the `PG*` vars (most libpq-based
drivers pick them up with no explicit connection args).

## Providing your project (Mode A vs Mode B)

- **Mode A (default):** clone inside the container at `~/code/<project>`. Lives in
  the `devuser-home` named volume - invisible to the host, wiped only by
  `docker compose down -v`.
- **Mode B (opt-in):** bind-mount a host checkout. Uncomment both lines in `.env`:
  ```
  COMPOSE_FILE=compose.yaml:compose.external-mount.yaml
  HOST_CODE_PATH=/absolute/path/to/your/project
  ```
  It appears at `~/code/project-external` (distinct path, never collides with a
  Mode A clone). Edits sync both ways with the host.

## Running multiple worktrees

Several worktrees at once, each its own dev-docker, all sharing `../shared-db`:

```bash
cp -r FullStackWebDevDocker FullStackWebDevDocker-wtB
# in -wtB/.env:  POSTGRES_DB=app_b   CONTAINER_NAME=fullstack-web-dev-wtB
cd FullStackWebDevDocker-wtB
docker compose -p fswdd-wtB up -d
```

Each copy gets its own `.env` and `devuser-home` volume, its own database on the
shared server, and **must use distinct dev-server ports** (host networking makes
ports global on the host, so two worktrees on the same port collide).

## How it is wired

- **Host networking** - the container shares the host's network stack: dev servers
  are reachable on the host at the same port (no mapping), and the shared DB is at
  `localhost:5433`.
- **`/home/devuser` is a named volume** (`devuser-home`) - IDE settings/license,
  caches, `~/.ssh`, zsh history, and the Mode A checkout survive restarts. Wiped
  only by `docker compose down -v` (which does NOT touch the shared DB).
- **Docker-in-Docker** - the host's `/var/run/docker.sock` is mounted in, so
  `docker` inside runs against the host engine (sibling containers). `DOCKER_GID`
  grants `devuser` access to the socket.
- **Playwright** browsers are baked at `/opt/ms-playwright` (owned by `devuser`),
  `PLAYWRIGHT_BROWSERS_PATH` exported - e2e tests run immediately. If your project
  pins a different Playwright version, re-run `npx playwright install` (no sudo).
- **Git identity** from `.env` is applied on every container start by
  `entrypoint.sh`; change it and `docker compose restart dev-env`.
- **SSH keys** at `~/.ssh/id_*` are auto-loaded by keychain each shell and persist
  in the home volume.

## Common operations

| Action | Command |
|--------|---------|
| Shell in | `./zsh-into-docker-container.sh` |
| Status / logs | `docker compose ps` / `docker compose logs -f dev-env` |
| Rebuild | `docker compose build` (`--no-cache` for a clean rebuild) |
| Stop, keep state | `docker compose down` |
| Stop, wipe this dev-docker | `docker compose down -v` (shared DB untouched) |
| Shared DB shell | `docker compose -f ../shared-db/compose.yaml exec postgres psql -U admin` |

## Troubleshooting

| Problem | Fix |
|---------|-----|
| WebStorm window doesn't appear | Run `./xhost-setup.sh` on the host (once per login). The error is `Can't connect to X11 window server using ':0'`. Verify `echo $DISPLAY` matches the host. |
| `psql` / app can't reach the DB | Is `../shared-db` Up (healthy)? Do `POSTGRES_USER`/`POSTGRES_PASSWORD`/`PG_HOST_PORT` match `../shared-db/.env`? Does this worktree's DB exist (`createdb $PGDATABASE`)? |
| Permission denied on Mode B code | `USER_ID`/`GROUP_ID` in `.env` must match host `id -u`/`id -g`. |
| `docker` fails inside container | `DOCKER_GID` must match `getent group docker \| cut -d: -f3`. |
| Startup / mount fails | A required `.env` var is unset - check `docker compose config`. |
| Slow GUI | Software rendering (`LIBGL_ALWAYS_SOFTWARE=1`); for GPU tweak `devices:` in `compose.yaml`. |
