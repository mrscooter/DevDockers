# General Dev Docker

A throwaway, containerized Linux box for **Python and C/C++ experiments**. No IDE: you work in the shell (zsh) with the latest stable compilers, and GUI apps open on your host display over X11. Isolation from the host is the point: the only host directory the container sees is `fast_share`, it has no access to the host Docker engine, its network is separate from the host's, and it runs its own Claude Code under its own login.

| Inside the image | |
|---|---|
| OS | Ubuntu 26.04 LTS |
| C/C++ compilers | GCC 16.2 (built from source, default `gcc`/`g++`), GCC 15 (`gcc-15`/`g++-15`), LLVM/Clang 23 (apt.llvm.org) incl. libc++, lld, lldb, clangd, clang-format, clang-tidy, sanitizers |
| C/C++ tooling | CMake 4.2, Ninja, Meson, Autotools, pkg-config, ccache, mold, gdb, valgrind, strace, ltrace, cppcheck, bear, doxygen + graphviz, conan, vcpkg (`/opt/vcpkg`) |
| Python | Python 3.14 (+ venv, dev headers; `python` = `python3`), `uv` |
| GUI | Typora (X11) |
| Shell / tools | zsh + Oh My Zsh + keychain, Claude Code CLI, git, gh, vim/nano/micro/bat, jq, tree, xclip |

---

## Setup from scratch

Steps 0-4 are on the **host**, run from this directory (`GeneralDevDocker/`); from step 5 you are **inside the container**.

### 0. Check prerequisites (host)

| Need | Check |
|---|---|
| Docker Engine + Compose v2 | `docker --version && docker compose version` |
| You are in the `docker` group | `getent group docker` lists you |
| X11 (for GUI apps) | `echo $DISPLAY` prints `:0` or similar (Wayland: needs XWayland) |
| `xhost` present | `command -v xhost` |
| Disk space | several GB for the image |

### 1. Configure `.env`

```bash
cp .env.example .env
```

Set `DEV_NAME` / `DEV_EMAIL` (your git identity inside the container) and `FASTSHARE_PATH` (absolute host dir for the `~/fast_share` bridge). The file documents every variable. Then create that directory on the host, before the first start (otherwise Docker creates a root-owned, unwritable one):

```bash
mkdir -p ~/fast_share_gdd       # set FASTSHARE_PATH in .env to this absolute path
```

### 2. Build the image

```bash
docker compose build          # first build is long: GCC is compiled from source
```

### 3. Start the container

```bash
./up.sh                       # grants X access for GUI apps, then starts detached
```

`./up.sh` wraps `docker compose up -d` and passes extra args through, e.g. `./up.sh --build --force-recreate` after a Dockerfile change (without `--force-recreate`, compose was seen to keep the old container running on the old image).

### 4. Get a shell inside

```bash
./zsh-into-docker-container.sh
```

### 5. First-time setup inside

```bash
generate-ssh-key              # this container's own SSH key - see "SSH keys"
claude                        # log in with whichever Claude account you want here
```

---

## Compilers

- Unversioned names point to the newest: `gcc`, `g++`, `cc`, `c++`, `cpp`, `gcov` -> GCC 16.2 (`/opt/gcc-16`); `clang`, `clang++`, `clangd`, `lld`, `lldb`, `llvm-*` -> LLVM 23 (`/usr/lib/llvm-23/bin` on PATH). GCC 15 stays available as `gcc-15` / `g++-15`. CMake picks up `cc` / `c++`, i.e. GCC 16.
- C++26: `g++ -std=c++26` (GCC 16 defaults to C++20). Reflection additionally needs `-freflection`, contracts `-fcontracts`; both are experimental in GCC 16 and not available in Clang 23 (no `<meta>`, no `pre`/`post`).
- Clang uses the system's GCC 15 libstdc++ by default. For newer library features use `clang++ -stdlib=libc++`, or point it at GCC 16's libstdc++ with `--gcc-install-dir=/opt/gcc-16/lib/gcc/x86_64-linux-gnu/16.2.0`.
- Binaries built by GCC 16 find its newer `libstdc++` at runtime via `/etc/ld.so.conf.d/gcc-16.conf`; no `LD_LIBRARY_PATH` needed.
- `vcpkg` lives in `/opt/vcpkg` (owned by devuser, `VCPKG_ROOT` set): update with `git -C /opt/vcpkg pull`. `conan` is image-managed: upgrade by rebuilding the image.

## SSH keys

The host `~/.ssh` is never mounted. The default is a **dedicated key per container**, generated inside:

```bash
generate-ssh-key
```

It creates `~/.ssh/id_ed25519` (refuses to overwrite an existing one), asks for a passphrase (set one: it protects the key file at rest), prints the public key and copies it to `~/fast_share/GeneralDevDocker_id_ed25519.pub`. Register that public key on GitHub / GitLab, as an account key or a per-repo deploy key. If it ever leaks, revoke just this key; host keys are unaffected. keychain loads `~/.ssh/id_*` in every new zsh session and asks for the passphrase once per container start.

Fallback, for a key you cannot replace (e.g. a server you cannot add a new public key to): hand-carry it through the bridge.

```bash
# on the host
cp ~/.ssh/<key> "$FASTSHARE_PATH"/
# inside the container (lists candidates if run bare)
import-ssh-keys-from-fastshare <key>
```

Keys live in the home volume: they survive restarts and rebuilds, and are deleted by `docker compose down -v`.

## Claude Code

The CLI is installed in the image, but nothing is shared with the host's Claude Code: no credentials, no settings. Log in inside (`claude`) with any account, and configure it as you like; everything lives in the home volume and survives rebuilds. The CLI updates itself there too.

The image ships a root-owned `/etc/claude-code/managed-settings.json` that denies Claude's `Read` / `Edit` on `~/.ssh/**`. Managed settings cannot be overridden by user or project settings. This is a guard against **accidental** reads (e.g. the key ending up in a transcript), not a hard boundary: Claude Code enforces it for its own file tools and for Bash commands it recognizes (`cat`, `head`, ...), but not for arbitrary programs, e.g. a Python script reading the file. What actually protects the key is its passphrase, and that it is a dedicated key you can revoke.

## Isolation and networking

- **No Docker access** - the host's `/var/run/docker.sock` is not mounted (access to it is root-equivalent on the host).
- **Only `fast_share`** is shared with the host filesystem. Everything else lives in the image or the `devuser-home` named volume.
- **Bridge network, no published ports** - outbound internet works normally, but services listening on the host's `127.0.0.1` are unreachable from the container, and nothing inside is reachable from the host. To open a server running inside from the host, add a `ports:` entry to `compose.yaml` (e.g. `- "127.0.0.1:8000:8000"`), make the server listen on `0.0.0.0`, and re-run `./up.sh`.
- **X11** - the host's `/tmp/.X11-unix` socket is mounted and `./up.sh` grants local X access (`xhost +local:`), so GUI apps open windows on the host display. `typora` is a wrapper that runs Typora with `--no-sandbox`: Chromium's own sandbox needs namespace syscalls that Docker's default seccomp profile blocks, and allowing them would weaken the whole container.

## How it is wired

- **`/home/devuser` is a named volume** (`devuser-home`) - `~/.ssh`, `~/.claude`, zsh history, your code and caches survive restarts and rebuilds. Wiped only by `docker compose down -v`. Files baked into the image's home (e.g. `.zshrc`) are copied into the volume only when it is first created, so later image rebuilds do not update them.
- **Git identity** from `.env` (`DEV_NAME` / `DEV_EMAIL`) is applied on every container start by `entrypoint.sh`; change it and `docker compose restart dev-env`.
- **devuser** has UID/GID 1000 and passwordless sudo.

## Common operations

| Action | Command |
|--------|---------|
| Shell in | `./zsh-into-docker-container.sh` |
| Status / logs | `docker compose ps` / `docker compose logs -f dev-env` |
| Rebuild + restart | `./up.sh --build --force-recreate` (`docker compose build --no-cache` for a clean rebuild) |
| Stop, keep state | `docker compose down` |
| Stop, wipe home volume (keys, Claude login, code) | `docker compose down -v` |

## Troubleshooting

| Problem | Fix |
|---------|-----|
| GUI window doesn't appear | Check `echo $DISPLAY` on the host and that you are in a graphical session (Wayland needs XWayland), then re-run `./xhost-setup.sh`. Error looks like `cannot open display`. |
| Startup / mount fails | A required `.env` var is unset - check `docker compose config`. |
| `Permission denied` in `~/fast_share` | The host dir must exist before the first start and be owned by `USER_ID:GROUP_ID`. |
| `git push` over SSH asks for a key / `permission denied (publickey)` | No key yet (`generate-ssh-key`), or its public key is not registered on the remote. |
| Slow GUI | Expected - rendering is software by default (`LIBGL_ALWAYS_SOFTWARE=1`). |
