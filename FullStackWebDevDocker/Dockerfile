FROM ubuntu:24.04

ARG USER_ID=1000
ARG GROUP_ID=1000

# Layer 1: Core system packages, editors, X11/DBus/GL libs for GUI apps,
# Playwright OS deps, Docker CLI (for DinD via host socket), keychain. One apt layer,
# cleanup in same RUN to keep image lean.
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates curl wget gnupg git make sudo zsh tree jq xclip \
        vim nano bat micro \
        python3 python3-venv \
        dbus dbus-x11 libgl1-mesa-dri libegl-mesa0 adwaita-icon-theme \
        gsettings-desktop-schemas at-spi2-core fonts-dejavu \
        libnss3 libatk-bridge2.0-0 libatk1.0-0 libcups2 libdrm2 libgbm1 \
        libxkbcommon0 libxcomposite1 libxdamage1 libxrandr2 libasound2t64 \
        libpangocairo-1.0-0 libpango-1.0-0 libcairo2 libxshmfence1 \
        docker.io keychain \
    && rm -rf /var/lib/apt/lists/*

# Layer 2: PostgreSQL client 16 from the PGDG apt repo (Ubuntu's default is older).
# We install ONLY the client - the Postgres server runs as a separate, shared
# standalone project (see ../shared-db), reached over the host at localhost:5433.
RUN install -d -m 755 /etc/apt/keyrings && \
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
        | gpg --dearmor -o /etc/apt/keyrings/postgresql.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt noble-pgdg main" \
        > /etc/apt/sources.list.d/pgdg.list && \
    apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        postgresql-client-16 && \
    rm -rf /var/lib/apt/lists/*

# Layer 3: Node.js 20 (NodeSource). Bump here if a project needs a newer line.
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

# Layer 4: WebStorm - pinned, sha256-verified, extracted to /opt/, symlinked.
# Note: download with original filename because JetBrains' .sha256 file references it.
RUN wget -q https://download.jetbrains.com/webstorm/WebStorm-2026.1.2.tar.gz && \
    wget -q https://download.jetbrains.com/webstorm/WebStorm-2026.1.2.tar.gz.sha256 && \
    sha256sum -c WebStorm-2026.1.2.tar.gz.sha256 && \
    tar -xzf WebStorm-2026.1.2.tar.gz -C /opt/ && \
    rm WebStorm-2026.1.2.tar.gz WebStorm-2026.1.2.tar.gz.sha256 && \
    ln -s /opt/WebStorm-*/bin/webstorm.sh /usr/local/bin/webstorm

# Layer 5: Free UID 1000 (Ubuntu base image's built-in `ubuntu` user) and create devuser.
# Using host UID 1000 means no chown of bind-mounted host directories needed.
RUN userdel -r ubuntu 2>/dev/null || true && \
    groupadd -g $GROUP_ID devgroup && \
    useradd -m -u $USER_ID -g $GROUP_ID devuser && \
    chsh -s /usr/bin/zsh devuser && \
    usermod -aG sudo devuser && \
    echo "devuser ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/devuser

# Layer 6: dbus machine-id (some GUI apps complain without it).
# Note: --ensure errors on Ubuntu 24.04's empty /etc/machine-id, so write directly.
RUN dbus-uuidgen > /etc/machine-id && \
    ln -sf /etc/machine-id /var/lib/dbus/machine-id

# Layer 7: Playwright browsers baked into /opt/ms-playwright (system-wide).
# Installed as root, then ownership handed to devuser so they can also upgrade later
# without sudo. OS deps are already installed in layer 1, so --with-deps is unnecessary.
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright
RUN npx --yes playwright@1.60.0 install chromium firefox webkit && \
    chown -R $USER_ID:$GROUP_ID /opt/ms-playwright

USER devuser
WORKDIR /home/devuser

# Layer 8: oh-my-zsh, plugins, .zshrc.
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended && \
    git clone https://github.com/zsh-users/zsh-autosuggestions .oh-my-zsh/custom/plugins/zsh-autosuggestions && \
    git clone https://github.com/zsh-users/zsh-syntax-highlighting .oh-my-zsh/custom/plugins/zsh-syntax-highlighting && \
    sed -i 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' .zshrc && \
    { \
      echo ''; \
      echo '# --- FullStackWebDevDocker additions ---'; \
      echo 'export NO_AT_BRIDGE=1'; \
      echo 'export LIBGL_ALWAYS_SOFTWARE=1'; \
      echo 'export PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright'; \
      echo '# docker exec gives a colorless TERM / no COLORTERM; advertise real capability for TUIs'; \
      echo 'export COLORTERM="${COLORTERM:-truecolor}"'; \
      echo '[[ "$TERM" == "xterm" || "$TERM" == "dumb" ]] && export TERM=xterm-256color'; \
      echo 'export PATH="$HOME/.local/bin:$HOME/.claude/local/bin:$PATH"'; \
      echo "alias bat='batcat'"; \
      echo 'export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-$(id -u)}"'; \
      echo 'mkdir -p "$XDG_RUNTIME_DIR" 2>/dev/null && chmod 700 "$XDG_RUNTIME_DIR" 2>/dev/null'; \
      echo '_keys=(~/.ssh/id_*(N))'; \
      echo '(( ${#_keys[@]} )) && eval "$(keychain --eval --quiet "${_keys[@]}" 2>/dev/null)"'; \
      echo '(( ${#_keys[@]} )) || {'; \
      echo '  print -r -- "No SSH key in ~/.ssh. To use one inside this container:"'; \
      echo '  print -r -- "  1. on the host, drop the private key into the fast_share dir (here: ~/fast_share)"'; \
      echo '  print -r -- "  2. in here, run: import-ssh-keys-from-fastshare <name>"'; \
      echo '}'; \
      echo 'unset _keys'; \
      echo '# Claude login share check (non-blocking FYI on shell entry).'; \
      echo 'if [[ ! -f ~/.claude/.credentials.json || ! -s ~/.claude/.credentials.json ]]; then'; \
      echo '  print -r -- "Note: host Claude login is NOT shared (~/.claude/.credentials.json missing or empty)."'; \
      echo '  print -r -- "  Fix on the HOST (log into Claude there; remove any stray dir Docker made at that path),"'; \
      echo '  print -r -- "  then recreate: docker compose up -d --force-recreate. Or run claude here to log in locally."'; \
      echo 'fi'; \
    } >> .zshrc

# Layer 9: uv (Astral) - fast Python package/venv manager for the backend.
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# Layer 10: Claude Code CLI.
RUN curl -fsSL https://claude.ai/install.sh | bash

ENV PATH="/home/devuser/.local/bin:/home/devuser/.claude/local/bin:${PATH}"

# Helper to bring a hand-carried SSH key from ~/fast_share into ~/.ssh (see README).
COPY import-ssh-keys-from-fastshare.sh /usr/local/bin/import-ssh-keys-from-fastshare

# Entrypoint applies git identity + the Claude bootstrap on every container start (so
# .env changes take effect without rebuilding the image or wiping the home volume).
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
ENTRYPOINT ["entrypoint.sh"]
CMD ["tail", "-f", "/dev/null"]
