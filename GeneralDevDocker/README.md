# General Dev Docker

A throwaway, containerized Linux box for **Python and C/C++ experiments**. No IDE: you work in the shell (zsh) with the latest stable compilers, and GUI apps open on your host display over X11. Isolation from the host is the point: the only host directory the container sees is `fast_share`, it has no access to the host Docker engine, it cannot reach services bound to the host's `127.0.0.1`, and it runs its own Claude Code under its own login. It is not a network or X11 sandbox: see "Isolation and networking".

| Inside the image | |
|---|---|
| OS | Ubuntu 26.04 LTS |
| C/C++ compilers | GCC 16.2 (built from source, default `gcc`/`g++`), GCC 15 (`gcc-15`/`g++-15`), LLVM/Clang 23 (apt.llvm.org) incl. libc++, lld, lldb, clangd, clang-format, clang-tidy, sanitizers |
| C/C++ tooling | CMake 4.2, Ninja, Meson, Autotools, pkg-config, ccache, mold, gdb, valgrind, strace, ltrace, cppcheck, bear, doxygen + graphviz, conan, vcpkg (`/opt/vcpkg`) |
| Python | Python 3.14 (+ venv, dev headers; `python` = `python3`), `uv` |
| GUI | Typora (X11) |
| Shell / tools | zsh + Oh My Zsh, Claude Code CLI, git, gh, vim/nano/micro/bat, jq, tree, xclip |

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

Set `DEV_NAME` / `DEV_EMAIL` (your git identity inside the container), `FASTSHARE_PATH` (absolute host dir for the `~/fast_share` bridge) and, if needed, `SSH_KEY_DIR` (see "SSH keys"). The file documents every variable. Then create that directory on the host, before the first start (otherwise Docker creates a root-owned, unwritable one):

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
./zsh-into-docker-container.sh    # first run after a reboot asks for the SSH key passphrases
```

### 5. First-time setup inside

```bash
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

Private keys stay on the host. `./zsh-into-docker-container.sh` runs a dedicated ssh-agent on the host, one per container (socket in `~/.local/state/<CONTAINER_NAME>-ssh/`), loads every key from the dedicated host directory `~/.ssh/<CONTAINER_NAME>/` into it (`SSH_KEY_DIR` in `.env` to change), and the container gets only the agent's socket (`SSH_AUTH_SOCK`). `git` / `ssh` inside authenticate through it, but there is no key file to read, not even with sudo.

`./up.sh` creates that directory and, while it holds no key, says so with its full path. Recommended: a dedicated key for the container, created there on the host (`general-dev` is the default `CONTAINER_NAME`):

```bash
ssh-keygen -t ed25519 -C general-dev -f ~/.ssh/general-dev/id_ed25519   # set a passphrase
sudo chown root:root ~/.ssh/general-dev/id_ed25519   # optional: unreadable for your user (Claude on the host); keep the dir and .pub yours
```

Register `~/.ssh/general-dev/id_ed25519.pub` on GitHub / GitLab, as an account key or a per-repo deploy key. If it ever leaks, revoke just this key. To use another host key in the container too, copy it with its `.pub` into the directory: every private key there that has its `.pub` next to it is loaded.

The first `./zsh-into-docker-container.sh` after a reboot asks on the host for each key's passphrase (plus your sudo password for a root-owned key); later runs reuse the agent. It is separate from your desktop's agent, so the container sees only the listed keys. Until reboot, the unlocked keys are usable, not readable, by everything in the container, Claude included, and by any host process of your user that uses that socket.

## Claude Code

The CLI is installed in the image, but nothing is shared with the host's Claude Code: no credentials, no settings. Log in inside (`claude`) with any account, and configure it as you like; everything lives in the home volume and survives rebuilds. The CLI updates itself there too.

The image ships a root-owned `/etc/claude-code/managed-settings.json` that denies Claude's `Read` / `Edit` on `~/.ssh/**`, in case a key is ever put there by hand (keys normally stay on the host, see "SSH keys"). User and project settings cannot override managed settings, but root can, and devuser (so Claude too) has passwordless sudo. It is a guard against **accidental** reads (e.g. a key ending up in a transcript), not a hard boundary: Claude Code enforces it for its own file tools and for Bash commands it recognizes (`cat`, `head`, ...), but not for arbitrary programs, e.g. a Python script reading the file.

Claude can use the SSH keys loaded in the host agent, e.g. for `git push`. This is intended: register a key only where Claude may act as you.

## Isolation and networking

- **No Docker access** - the host's `/var/run/docker.sock` is not mounted (access to it is root-equivalent on the host).
- **Only `fast_share`** is shared with the host filesystem, plus two sockets: X11 (below) and the host ssh-agent (see "SSH keys"). Everything else lives in the image or the `devuser-home` named volume.
- **Bridge network, no published ports** - outbound traffic is NATed through the host, so the container reaches whatever the host reaches: the internet, the LAN, VPN / mesh peers (Tailscale, NetBird, ...), and host services listening on `0.0.0.0` (via the bridge gateway IP). Only services bound to the host's `127.0.0.1` are unreachable. The other direction is open too: on Linux the host can connect to the container's IP directly. For a stable address, add a `ports:` entry to `compose.yaml` (e.g. `- "127.0.0.1:8000:8000"`), make the server inside listen on `0.0.0.0`, and re-run `./up.sh`.
- **X11** - the host's `/tmp/.X11-unix` socket is mounted and `./up.sh` grants X access to your host UID (`xhost +SI:localuser:<you>`), which the container runs as, so GUI apps open windows on the host display. Accepted risk: X11 does not isolate clients from each other, so any process in the container, Claude included, can read the host clipboard, and capture and send keystrokes to every X11 / XWayland window on the host (e.g. JetBrains IDEs, which run on XWayland by default). Wayland-native host apps are exposed only through the clipboard. The grant lasts until the X server exits (logout); revoke earlier with `xhost -SI:localuser:$USER`. `typora` is a wrapper that runs Typora with `--no-sandbox`: Chromium's own sandbox needs namespace syscalls that Docker's default seccomp profile blocks, and allowing them would weaken the whole container.

## How it is wired

- **`/home/devuser` is a named volume** (`devuser-home`) - `~/.ssh`, `~/.claude`, zsh history, your code and caches survive restarts and rebuilds. Wiped only by `docker compose down -v`. Files baked into the image's home (e.g. Oh My Zsh's `.zshrc`) are copied into the volume only when it is first created, so later image rebuilds do not update them. The image's own shell setup therefore lives in `/etc/zsh/zshrc`.
- **Git identity** from `.env` (`DEV_NAME` / `DEV_EMAIL`) is applied on every container start by `entrypoint.sh`; change it and `docker compose restart dev-env`.
- **devuser** has UID/GID 1000 and passwordless sudo, deliberately: the container is a space where Claude can do anything without permission prompts, including breaking it.

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
| `git push` over SSH: `permission denied (publickey)` | `ssh-add -l` inside lists the loaded keys. None / `Error connecting to agent`: no key with its `.pub` in `~/.ssh/<CONTAINER_NAME>/`, or no shell opened via `./zsh-into-docker-container.sh` since the last reboot. Key listed: its public key is not registered on the remote. |
| `bind: Permission denied` from ssh-agent | A plain `docker compose up` created `~/.local/state/<CONTAINER_NAME>-ssh` root-owned: `sudo chown $USER: ~/.local/state/<CONTAINER_NAME>-ssh`, then start via `./up.sh`. |
| Slow GUI | Expected - rendering is software by default (`LIBGL_ALWAYS_SOFTWARE=1`). |
