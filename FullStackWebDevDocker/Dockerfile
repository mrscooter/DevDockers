FROM ubuntu:24.04

# Fail a RUN when any command in a pipe fails, not just the last one: a `curl | bash`
# installer whose download failed would otherwise build a layer without the tool.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG USER_ID=1000
ARG GROUP_ID=1000

# Layer 1: Core system packages, editors, X11/DBus/GL + GUI shared libs (for the WebStorm
# GUI; Playwright's full browser deps come via --with-deps in layer 7, not here).
# One apt layer, cleanup in same RUN to stay lean.
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates curl wget gnupg git make sudo zsh tree jq xclip iproute2 \
        openssh-client \
        vim nano bat micro less \
        python3 python3-venv \
        dbus dbus-x11 libgl1-mesa-dri libegl-mesa0 adwaita-icon-theme \
        gsettings-desktop-schemas at-spi2-core fonts-dejavu \
        libnss3 libatk-bridge2.0-0 libatk1.0-0 libcups2 libdrm2 libgbm1 \
        libxkbcommon0 libxcomposite1 libxdamage1 libxrandr2 libasound2t64 \
        libpangocairo-1.0-0 libpango-1.0-0 libcairo2 libxshmfence1 \
    && rm -rf /var/lib/apt/lists/*

# Layer 2: Tools from official apt repos (Ubuntu's are older/absent) - PostgreSQL
# client 16 (PGDG) and GitHub CLI (gh). Postgres: client only; the server runs as a
# separate shared project (see ../shared-db), reached at localhost:5433.
RUN install -d -m 755 /etc/apt/keyrings && \
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
        | gpg --dearmor -o /etc/apt/keyrings/postgresql.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt noble-pgdg main" \
        > /etc/apt/sources.list.d/pgdg.list && \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /etc/apt/keyrings/githubcli-archive-keyring.gpg && \
    chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list && \
    apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        postgresql-client-16 gh && \
    rm -rf /var/lib/apt/lists/*

# Layer 2b: Typora (markdown editor, GUI over X11 like WebStorm; commercial app with
# a free trial). Installed from the direct CDN host download.typora.io rather than the
# typora.io/linux apt repo: that repo's origin intermittently 526s behind Cloudflare,
# which fails the whole build. The direct host is healthy. Version pinned for repro.
RUN curl -fsSL -o /tmp/typora.deb \
        https://download.typora.io/linux/typora_1.13.6_amd64.deb && \
    apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        /tmp/typora.deb && \
    rm -f /tmp/typora.deb && \
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

# Layer 7: Playwright browsers baked into /opt/ms-playwright (system-wide), WITH their
# OS shared-library deps. --with-deps apt-installs the full browser dep set: Chromium,
# Firefox AND WebKit need libs (libgtk-3/4, libgstreamer, libXfixes, libXcursor, ...)
# a hand-picked subset misses, so browsers fail to launch without it. Run as root at
# build; browsers chowned to devuser so they can be upgraded later without sudo.
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright
RUN npx --yes playwright@1.60.0 install --with-deps chromium firefox webkit && \
    chown -R $USER_ID:$GROUP_ID /opt/ms-playwright && \
    rm -rf /var/lib/apt/lists/*

# Layer 8: shell setup in the system-wide /etc/zsh/zshrc (sourced before ~/.zshrc), not
# in the home volume, so image rebuilds reach existing volumes too.
RUN { \
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
      echo '# Claude login check (non-blocking FYI on shell entry; the login is container-local, not the host one).'; \
      echo 'if [[ ! -s ~/.claude/.credentials.json ]]; then'; \
      echo '  print -r -- "Note: Claude is not logged in inside this container (separate from the host login)."'; \
      echo '  print -r -- "  Run claude and log in; the login persists in the home volume."'; \
      echo 'fi'; \
    } >> /etc/zsh/zshrc

USER devuser
WORKDIR /home/devuser

# Layer 9: oh-my-zsh, plugins.
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended && \
    git clone https://github.com/zsh-users/zsh-autosuggestions .oh-my-zsh/custom/plugins/zsh-autosuggestions && \
    git clone https://github.com/zsh-users/zsh-syntax-highlighting .oh-my-zsh/custom/plugins/zsh-syntax-highlighting && \
    sed -i 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' .zshrc

# Layer 10: uv (Astral) - fast Python package/venv manager for the backend.
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# Layer 11: Claude Code CLI.
RUN curl -fsSL https://claude.ai/install.sh | bash

ENV PATH="/home/devuser/.local/bin:/home/devuser/.claude/local/bin:${PATH}"

# Entrypoint applies git identity + the Claude bootstrap on every container start (so
# .env changes take effect without rebuilding the image or wiping the home volume).
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
ENTRYPOINT ["entrypoint.sh"]
CMD ["tail", "-f", "/dev/null"]
