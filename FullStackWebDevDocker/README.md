# Full-Stack Web Dev Docker

A throwaway, containerized dev environment for **any** full-stack web project - Python backend + Node frontend + PostgreSQL (Django + React, FastAPI + Vue, Flask + Svelte, ...). It bundles the runtimes/tooling, but no IDE (install one per container, see [step 9](#9-run-it)), so your work - including AI agents you let loose inside - stays isolated from the host: the only host files touched are your project checkout (and only if you opt in).

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
| OS | Ubuntu 26.04 LTS |
| Backend | Python 3.14 + `uv` (Astral); `gcc` / `g++` + Python headers, only for building packages that ship no wheel |
| Frontend | Node.js 24 + npm, Playwright browser OS libs (browsers per project) |
| DB client | `psql` / `pg_dump` (postgresql-client-16) |
| GUI | X11 forwarding and the GUI libs VS Code and JetBrains IDEs need, for apps you install into your home (none preinstalled) |
| Shell / tools | zsh + Oh My Zsh, Claude Code CLI, git, gh, make, vim/nano/micro/bat, jq, tree, xclip |

---

## Setup from scratch

Run these in order. Steps 0-4 are on the **host**; from step 5 you are **inside the container**. Host-side commands assume you start in this directory (`FullStackWebDevDocker/`).

### 0. Check prerequisites (host)

| Need | Check |
|---|---|
| Docker Engine + Compose v2 | `docker --version && docker compose version` |
| You are in the `docker` group | `getent group docker` lists you; else `sudo usermod -aG docker $USER && newgrp docker` |
| X11 (for GUI apps you install) | `echo $DISPLAY` prints `:0` or similar (Wayland: needs XWayland) |
| `xhost` present | `command -v xhost` |
| ~3 GB free disk | image is ~2 GB |

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
| `POSTGRES_USER` / `POSTGRES_PASSWORD` / `PG_HOST_PORT` | **must match `../shared-db/.env`** |
| `POSTGRES_DB` | this worktree's database name (default `devdocker_default_db`) |
| `FASTSHARE_PATH` | host dir: absolute, `~/...`, or `./`-relative to this directory; a bare name without `./` is a Docker volume (must exist, owned by `USER_ID:GROUP_ID`) bridged to `~/fast_share` |

Defaults for everything else are fine on a typical UID-1000 Linux desktop. The Claude login is separate from the host's, so you log in once inside the container - see [Claude integration](#claude-integration). Validate with `docker compose config` if unsure.

Then create the `FASTSHARE_PATH` directory on the host (it must exist before you start the container, or the bind-mount creates a root-owned, unwritable one):

```bash
mkdir -p ~/fast_share_fswdd       # then set FASTSHARE_PATH=~/fast_share_fswdd in .env
```

### 3. Build the image

```bash
docker compose build          # first build takes a few minutes (apt, Playwright OS libs)
```

### 4. Start the container

```bash
./up.sh                       # grants X access for the GUI, then starts detached
docker compose ps             # dev-env should be Up
```

`./up.sh` wraps `docker compose up -d`: it first grants the X server access so GUI apps can open windows (warning loudly, but still starting, if there is no display to reach) and creates the ssh-agent socket and SSH key dirs (see [SSH keys](#ssh-keys)), then starts the container in the background with `--build`, so Dockerfile changes always reach the container (the image is rebuilt from cache; nothing changed = a few seconds, container left running). Re-run it any time - the X grant is idempotent. Extra args pass through to `docker compose up`, e.g. `./up.sh --force-recreate`.

### 5. Get a shell inside

```bash
./zsh-into-docker-container.sh    # first run after a reboot asks for the SSH key passphrases
```

Everything below runs inside the container.

### 6. Get your project into the container

Default (Mode A) - clone it inside; lives in the container's named volume:

```bash
mkdir -p ~/code && cd ~/code
git clone <your-project-url> <project>
```

Cloning a private repo over SSH? Put your key into `~/.ssh/fullstack-web-dev/` on the host first, or this fails with `permission denied (publickey)` - see [SSH keys](#ssh-keys).

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
( cd <frontend-dir> && npx playwright install )   # e2e browsers, if the project uses Playwright
```

If the project has its own setup command (e.g. `make setup`), run that instead; it usually covers these. `uv sync` uses the image's Python 3.14 when it satisfies the project's `requires-python` / `.python-version`, otherwise uv downloads a matching Python.

Point your app at the DB via the `PG*` connection vars plus an explicit database name (the `BASE_DEV_DB_URL` template is a handy starting point) - see [Database connection](#database-connection).

### 9. Run it

Launch your backend + frontend dev servers on this worktree's ports; with host networking they are reachable from the host browser at the same port.

No IDE is included. If you want one in this container, install it into your home (e.g. a JetBrains IDE tarball unpacked under `~/.local`), where it survives recreates, and start it from the shell; its window opens on your host display.

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

The container runs its own Claude Code CLI with its own login and config, without baking anything machine-specific into the image.

- **Login (container-local).** Nothing from the host's `~/.claude` is mounted, so the host login never reaches the container. Run `claude` inside the container and log in (open the URL it prints in your host browser). The login lands in `~/.claude/.credentials.json` in the home volume: it survives restarts and is wiped only by `docker compose down -v`. Host and container are separate logins.
- **Config (none installed).** The image sets up no Claude config: no instructions, skills or status line. Configure it inside the container as you like; it persists in the home volume. The entrypoint keeps a checkout of nicnajder-general-utils in `~/Tools` (see [How it is wired](#how-it-is-wired)) but wires nothing from it into `~/.claude`. Home volumes set up by the earlier Claude bootstrap still hold its `~/.claude/CLAUDE.md` and skill symlinks into that checkout, so they now follow its `master` on every start.

## SSH keys

The host `~/.ssh` is deliberately **not** mounted, and no private key ever enters the container, so unrelated keys (e.g. company keys) never reach a container you may run AI agents inside. `./zsh-into-docker-container.sh` runs a dedicated ssh-agent on the host, one per container (socket in `~/.local/state/<CONTAINER_NAME>-ssh/`), loads every key from the dedicated host directory `~/.ssh/<CONTAINER_NAME>/` into it (`SSH_KEY_DIR` in `.env` to change), and the container gets only the agent's socket (`SSH_AUTH_SOCK`). `git` / `ssh` inside authenticate through it, but there is no key file to read, not even with sudo.

`./up.sh` creates that directory and, while it holds no key, says so with its full path. Put the key(s) the container may use there (`fullstack-web-dev` is the default `CONTAINER_NAME`), each with its `.pub` next to it:

```bash
cp -p ~/.ssh/id_ed25519{,.pub} ~/.ssh/fullstack-web-dev/          # an existing key, or ssh-keygen a dedicated one there
sudo chown root:root ~/.ssh/fullstack-web-dev/id_ed25519          # optional: unreadable for your user (Claude on the host); keep the dir and .pub yours
```

The first `./zsh-into-docker-container.sh` after a reboot asks on the host for each key's passphrase (plus your sudo password for a root-owned key); later runs reuse the agent. It is separate from your desktop's agent, so the container sees only the keys in that directory. Until reboot, the unlocked keys are usable, not readable, by everything in the container, Claude included (e.g. `git push`), and by any host process of your user that uses that socket.

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
# in -wtB/.env:  POSTGRES_DB=app_b   CONTAINER_NAME=fullstack-web-dev-wtB   SSH_KEY_DIR=~/.ssh/fullstack-web-dev
cd FullStackWebDevDocker-wtB
./up.sh                        # the copied directory's name keeps it a separate compose project
```

Each copy gets its own `.env` and `devuser-home` volume (so its own Playwright browsers too), its own database on the shared server, and **must use distinct dev-server ports** (host networking makes ports global on the host, so two worktrees on the same port collide). Each has its own Claude login (it lives in the home volume, so log in once per copy); give each its own `FASTSHARE_PATH` if you want separate bridges. Each also gets its own host ssh-agent; `SSH_KEY_DIR` above shares the original's keys, leave it out to use `~/.ssh/<CONTAINER_NAME>/` instead.

## How it is wired

- **Host networking** - the container shares the host's network stack: dev servers are reachable on the host at the same port (no mapping), and the shared DB is at `localhost:5433`.
- **`/home/devuser` is a named volume** (`devuser-home`) - IDEs you install, their settings/license, caches, zsh history, and the Mode A checkout survive restarts. Wiped only by `docker compose down -v` (which does NOT touch the shared DB). Files baked into the image's home (e.g. Oh My Zsh's `.zshrc`) are copied into the volume only when it is first created, so the image's own shell setup lives in `/etc/zsh/zshrc`, which rebuilds do update.
- **No Docker access from inside** - the host's `/var/run/docker.sock` is deliberately not mounted: access to it is root-equivalent on the host, which would void the isolation (incl. of host SSH keys and the Claude login).
- **Playwright** - the image has the browsers' OS libraries only. The browsers must match each project's Playwright version, so the project installs them (`npx playwright install`, no sudo; e.g. in its `make setup`) into `~/.cache/ms-playwright` in the home volume, where they survive recreates and are shared by projects on the same Playwright version. Worktree copies have their own home volume, so each installs its own.
- **`entrypoint.sh`** runs on every container start: applies the git identity from `.env` (change it and `docker compose restart dev-env`), adds micro editor defaults (soft wrap) where unset, and updates the utils checkout below.
- **`~/Tools/nicnajder-general-utils`** - `entrypoint.sh` clones [mrscooter/nicnajder-general-utils](https://github.com/mrscooter/nicnajder-general-utils) there on the first start and brings its `master` up to date on every start: fast-forwarded when checked out, otherwise only the `master` ref moves. The update fetches anonymously over HTTPS; `origin` is set to the SSH address for your own pull / push. Offline or a diverged `master` only prints a warning. There is no switch to turn it off.
- **Claude** has its own container-local login and config (not the host's) - see [Claude integration](#claude-integration).
- **SSH keys** never enter the container: it uses a per-container host-side ssh-agent through a mounted socket - see [SSH keys](#ssh-keys).
- **X11** - the host's `/tmp/.X11-unix` socket is mounted and `./up.sh` grants X access to your host UID (`xhost +SI:localuser:<you>`), which the container runs as, so GUI apps you install open windows on the host display. Accepted risk: X11 does not isolate clients from each other, so any process in the container, Claude included, can read the host clipboard, and capture and send keystrokes to every X11 / XWayland window on the host (e.g. JetBrains IDEs, which run on XWayland by default). Wayland-native host apps are exposed only through the clipboard. The grant lasts until the X server exits (logout); revoke earlier with `xhost -SI:localuser:$USER`. Chromium / Electron-based apps you install (e.g. VS Code) need `--no-sandbox`: Chromium's own sandbox needs namespace syscalls that Docker's default seccomp profile blocks, and allowing them would weaken the whole container.

## Common operations

| Action | Command |
|--------|---------|
| Shell in | `./zsh-into-docker-container.sh` |
| Status / logs | `docker compose ps` / `docker compose logs -f dev-env` |
| Rebuild + restart | `./up.sh` (rebuilds from cache; `docker compose build --no-cache` for a clean rebuild) |
| Stop, keep state | `docker compose down` |
| Stop, wipe this dev-docker | `docker compose down -v` (shared DB untouched) |
| Shared DB shell | `docker compose -f ../shared-db/compose.yaml exec postgres psql -U admin` |

## Troubleshooting

| Problem | Fix |
|---------|-----|
| GUI window doesn't appear | `./up.sh` grants X access for you; if it still won't open you likely have no reachable display. Check `echo $DISPLAY` is set and you're in a graphical session (Wayland needs XWayland), then re-run `./xhost-setup.sh`. Error looks like `Can't connect to X11 window server`. |
| `psql` / app can't reach the DB | Is `../shared-db` Up (healthy)? Do `POSTGRES_USER`/`POSTGRES_PASSWORD`/`PG_HOST_PORT` match `../shared-db/.env`? There's no ambient DB - are you naming one (`psql -d <db>`)? Does it exist (`createdb <db>`)? |
| Permission denied on Mode B code | `USER_ID`/`GROUP_ID` in `.env` must match host `id -u`/`id -g`. |
| Startup / mount fails | A required `.env` var is unset - check `docker compose config`. |
| `git push` over SSH: `permission denied (publickey)` | `ssh-add -l` inside lists the loaded keys. None / `Error connecting to agent`: no key with its `.pub` in `~/.ssh/<CONTAINER_NAME>/`, or no shell opened via `./zsh-into-docker-container.sh` since the last reboot. Key listed: its public key is not registered on the remote. |
| `bind: Permission denied` from ssh-agent | A plain `docker compose up` created `~/.local/state/<CONTAINER_NAME>-ssh` root-owned: `sudo chown $USER: ~/.local/state/<CONTAINER_NAME>-ssh`, then start via `./up.sh`. |
| Slow GUI | Expected - rendering is software by default (`LIBGL_ALWAYS_SOFTWARE=1`). For GPU acceleration, add a `devices: ["/dev/dri/renderD128:/dev/dri/renderD128"]` block to `compose.yaml` and unset `LIBGL_ALWAYS_SOFTWARE`. |
