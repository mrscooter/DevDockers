# Full-Stack Web Dev Docker

A throwaway, containerized dev environment for **any** full-stack web project - Python backend + Node frontend + PostgreSQL (Django + React, FastAPI + Vue, Flask + Svelte, ...). It bundles the IDE and all the runtimes/tooling so your work - including AI agents you let loose inside - stays isolated from the host: the only host files touched are your project checkout (and only if you opt in).

The image ships runtimes, not your app. Your project's own dependencies arrive when you run `uv sync` / `npm ci` against its lockfiles inside the container.

**The database lives outside this project.** Postgres runs once as a separate shared service ([../shared-db](../shared-db/)); every dev-docker - including several worktrees at once - connects to it at `localhost:5433`. That is what lets you run multiple worktrees simultaneously without database port clashes.

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

Run these in order. Steps 0-4 are on the **host**; from step 5 you are **inside the container**. Host-side commands assume you start in this directory (`FullStackWebDevDocker/`).

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
| `POSTGRES_DB` | this worktree's database name (default `devdocker_default_db`) |
| `FASTSHARE_PATH` | absolute host dir (must exist, owned by `USER_ID:GROUP_ID`) bridged to `~/fast_share` - see [SSH keys](#ssh-keys) |

Defaults for everything else are fine on a typical UID-1000 Linux desktop. Claude login + skills work out of the box if you have logged into Claude on the host once - see [Claude integration](#claude-integration). Validate with `docker compose config` if unsure.

Then create the `FASTSHARE_PATH` directory on the host (it must exist before you start the container, or the bind-mount creates a root-owned, unwritable one):

```bash
mkdir -p ~/fast_share_fswdd       # set FASTSHARE_PATH in .env to this absolute path
```

### 3. Build the image

```bash
docker compose build          # first build ~10-15 min (WebStorm, Playwright, apt)
```

### 4. Start the container

```bash
./up.sh                       # grants X access for the GUI, then starts detached
docker compose ps             # dev-env should be Up
```

`./up.sh` wraps `docker compose up -d`: it first grants the X server access so the WebStorm GUI can open windows (warning loudly, but still starting, if there is no display to reach), then starts the container in the background. Re-run it any time - the X grant is idempotent. Extra args pass through to `docker compose up`, e.g. `./up.sh --build` or `./up.sh --force-recreate` (after editing `.env`).

### 5. Get a shell inside

```bash
./zsh-into-docker-container.sh
```

Everything below runs inside the container.

### 6. Get your project into the container

Default (Mode A) - clone it inside; lives in the container's named volume:

```bash
mkdir -p ~/code && cd ~/code
git clone <your-project-url> <project>
```

Cloning a private repo over SSH? Import your key first, or this fails with `permission denied (publickey)` - see [SSH keys](#ssh-keys).

(Alternative Mode B mounts a host checkout instead - see [Providing your project](#providing-your-project-mode-a-vs-mode-b).)

### 7. Create this worktree's database

The shared server hosts one database per worktree; create yours (the `PG*` vars supply the connection - just name the DB explicitly):

```bash
createdb my_worktree_db        # use the DB name your app's .env / DATABASE_URL points at
```

### 8. Install project deps and wire up the DB

```bash
cd ~/code/<project>
uv sync                                   # backend deps
( cd <frontend-dir> && npm ci )           # frontend deps
```

Point your app at the DB via the `PG*` connection vars plus an explicit database name (the `BASE_DEV_DB_URL` template is a handy starting point) - see [Database connection](#database-connection).

### 9. Run it

```bash
webstorm &                                # IDE window opens on your host display
# launch your backend + frontend dev servers on this worktree's ports;
# with host networking they are reachable from the host browser at the same port.
```

First WebStorm launch: activate your JetBrains license once (it persists in the named volume).

That is the whole setup. The sections below are reference.

---

## Database connection

Postgres runs in [../shared-db](../shared-db/), reachable inside the container at `localhost:5433`. The container pre-exports only the libpq **connection** vars (host/port/user/password from your `.env`) - **not** the database, on purpose, so nothing silently uses a shared default:

```bash
echo $PGHOST:$PGPORT      # localhost:5433
echo $BASE_DEV_DB_URL     # postgresql://admin:devPass77@localhost:5433/devdocker_default_db
psql -d <your_db>         # bare `psql` has no default DB - always pass -d
```

`BASE_DEV_DB_URL` is a **template only**. It is deliberately not named `DATABASE_URL`, so no framework auto-consumes it (and it can't shadow a worktree's own `.env`). It points at the shared *default* database; for a real project set your app's own DB config - typically this same string with the database name swapped for your worktree's DB.

Each worktree picks its DB explicitly, so several can share the one server without colliding. Wiring Django from the `PG*` connection vars plus an explicit name:

```python
import os
DATABASES = {"default": {
    "ENGINE": "django.db.backends.postgresql",
    "NAME": "my_worktree_db",                       # this worktree's DB (you created it)
    "USER": os.environ["PGUSER"], "PASSWORD": os.environ["PGPASSWORD"],
    "HOST": os.environ["PGHOST"], "PORT": os.environ["PGPORT"],
}}
```

Or have the app read its own `DATABASE_URL` (e.g. `dj-database-url` / `django-environ`), set in the project's `.env` to `BASE_DEV_DB_URL` with the DB name swapped.

## Claude integration

The container runs its own Claude Code CLI but reuses **your** account and personal setup, without baking anything machine-specific into the image. Three independent pieces:

- **Login (seeded from the host).** `compose.yaml` bind-mounts the host's `${HOST_CLAUDE_DIR:-~/.claude}/.credentials.json` read-only at a staging path, and `entrypoint.sh` copies it into the container's `~/.claude/` on every container start - so you do not log in again inside the container, and the container refreshes its own copy independently from there. (It cannot be mounted at the real path directly: Claude Code replaces the file via rename on every token refresh, and a single-file bind mount pins the inode - the container's view goes stale and starts 401ing once the old token expires.) Prerequisite: you have logged into Claude on the host at least once, so the host file exists. Only the credentials file is shared - the rest of `~/.claude` is container-local. If the container's login ever goes stale anyway (claude reports 401 / asks to `/login`), `docker compose restart` re-seeds it from the host's current login.
- **Skills + global instructions (bootstrapped on first start).** `entrypoint.sh` clones the public utils repo to `~/Tools/nicnajder-general-utils`, symlinks its `GLOBAL-GENERAL-CLAUDE.md` and every skill into `~/.claude`, and writes a `~/.claude/CLAUDE.md` that imports only the universal rules (no Mercury). It runs every start but is idempotent (create-only-if-absent), so it is a no-op after the first; results persist in the home volume.
- **Keeping it fresh.** The instruction file and skills are symlinks into the clone, so editing files in the repo is reflected live. To pull *new commits*, reset the generated `CLAUDE.md`, or re-point the symlinks, set `CLAUDE_BOOTSTRAP_FORCE=true` in `.env` and `docker compose restart dev-env` (then set it back to `false`).

All of this is configurable in `.env` (`HOST_CLAUDE_DIR`, `CLAUDE_BOOTSTRAP`, `CLAUDE_BOOTSTRAP_FORCE`, `CLAUDE_UTILS_REPO`, `CLAUDE_UTILS_DIR`); set `CLAUDE_BOOTSTRAP=false` to skip the bootstrap entirely.

## SSH keys

The host `~/.ssh` is deliberately **not** mounted, so unrelated keys (e.g. company keys) never leak into a container you may run AI agents inside. Instead you hand-carry only the key(s) you want, through the `~/fast_share` bridge (`FASTSHARE_PATH` on the host):

```bash
# on the host: put the key on the bridge
cp ~/.ssh/id_ed25519 "$FASTSHARE_PATH"/

# inside the container: import it (sets perms; lists candidates if run bare)
import-ssh-keys-from-fastshare id_ed25519
```

The key is copied into the container-private `~/.ssh` (chmod 600) and persists in the home volume. keychain auto-loads `~/.ssh/id_*` on each new zsh session; until a key is present, a shell prints a one-time reminder pointing at this flow. You can then delete the copy from `fast_share` if you do not want it lingering on the bridge.

## Providing your project (Mode A vs Mode B)

- **Mode A (default):** clone inside the container at `~/code/<project>`. Lives in the `devuser-home` named volume - invisible to the host, wiped only by `docker compose down -v`.
- **Mode B (opt-in):** bind-mount a host checkout. Uncomment both lines in `.env`:
  ```
  COMPOSE_FILE=compose.yaml:compose.external-mount.yaml
  HOST_CODE_PATH=/absolute/path/to/your/project
  ```
  It appears at `~/code/project-external` (distinct path, never collides with a Mode A clone). Edits sync both ways with the host.

## Running multiple worktrees

Several worktrees at once, each its own dev-docker, all sharing `../shared-db`:

```bash
cp -r FullStackWebDevDocker FullStackWebDevDocker-wtB
# in -wtB/.env:  POSTGRES_DB=app_b   CONTAINER_NAME=fullstack-web-dev-wtB
cd FullStackWebDevDocker-wtB
docker compose -p fswdd-wtB up -d
```

Each copy gets its own `.env` and `devuser-home` volume, its own database on the shared server, and **must use distinct dev-server ports** (host networking makes ports global on the host, so two worktrees on the same port collide). They all share the one host Claude login (`.credentials.json`), and the bootstrap runs once per volume; give each its own `FASTSHARE_PATH` if you want separate bridges.

## How it is wired

- **Host networking** - the container shares the host's network stack: dev servers are reachable on the host at the same port (no mapping), and the shared DB is at `localhost:5433`.
- **`/home/devuser` is a named volume** (`devuser-home`) - IDE settings/license, caches, `~/.ssh`, zsh history, and the Mode A checkout survive restarts. Wiped only by `docker compose down -v` (which does NOT touch the shared DB).
- **Docker-in-Docker** - the host's `/var/run/docker.sock` is mounted in, so `docker` inside runs against the host engine (sibling containers). `DOCKER_GID` grants `devuser` access to the socket.
- **Playwright** browsers are baked at `/opt/ms-playwright` (owned by `devuser`), `PLAYWRIGHT_BROWSERS_PATH` exported - e2e tests run immediately. If your project pins a different Playwright version, re-run `npx playwright install` (no sudo).
- **Git identity** from `.env` is applied on every container start by `entrypoint.sh`; change it and `docker compose restart dev-env`.
- **Claude** login is shared from the host and skills/instructions are bootstrapped on first start - see [Claude integration](#claude-integration).
- **SSH keys** are NOT mounted from the host. You hand-carry the one(s) you want via `~/fast_share` - see [SSH keys](#ssh-keys). Once in `~/.ssh/id_*` they are auto-loaded by keychain each shell and persist in the home volume.

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
| WebStorm window doesn't appear | `./up.sh` grants X access for you; if it still won't open you likely have no reachable display. Check `echo $DISPLAY` is set and you're in a graphical session (Wayland needs XWayland), then re-run `./xhost-setup.sh`. Error looks like `Can't connect to X11 window server`. |
| `psql` / app can't reach the DB | Is `../shared-db` Up (healthy)? Do `POSTGRES_USER`/`POSTGRES_PASSWORD`/`PG_HOST_PORT` match `../shared-db/.env`? There's no ambient DB - are you naming one (`psql -d <db>`)? Does it exist (`createdb <db>`)? |
| Permission denied on Mode B code | `USER_ID`/`GROUP_ID` in `.env` must match host `id -u`/`id -g`. |
| `docker` fails inside container | `DOCKER_GID` must match `getent group docker \| cut -d: -f3`. |
| Startup / mount fails | A required `.env` var is unset - check `docker compose config`. |
| Slow GUI | Expected - rendering is software by default (`LIBGL_ALWAYS_SOFTWARE=1`). For GPU acceleration, add a `devices: ["/dev/dri/renderD128:/dev/dri/renderD128"]` block to `compose.yaml` and unset `LIBGL_ALWAYS_SOFTWARE`. |
