# Stage 1: GCC from source. Ubuntu 26.04 ships GCC 15 as default and only a pre-release
# snapshot of gcc-16, so the latest stable GCC is built here (C++26 reflection/contracts).
# Installed to /opt/gcc-16 and copied into the final image; this stage is layer-cached.
FROM ubuntu:26.04 AS gcc-build

ARG GCC_VERSION=16.2.0
ARG GCC_SHA512=c51c30ca7422d0cbecf504b2e0f33c3aca31e0f90a76b65217f465163fa6fa17b3f5de39e145c47e5bab90ac0ce7fff3b03c8d553ae36e01faaea5a50f8648d1

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates wget xz-utils build-essential \
        libgmp-dev libmpfr-dev libmpc-dev libisl-dev zlib1g-dev libzstd-dev \
    && rm -rf /var/lib/apt/lists/*

# --build from dpkg-architecture so GCC picks up Ubuntu's multiarch layout
# (/usr/lib/x86_64-linux-gnu etc.); --disable-bootstrap since the host GCC 15 is trusted.
WORKDIR /tmp/gcc
RUN wget -q https://sourceware.org/pub/gcc/releases/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.xz && \
    echo "${GCC_SHA512}  gcc-${GCC_VERSION}.tar.xz" | sha512sum -c - && \
    tar -xf gcc-${GCC_VERSION}.tar.xz && \
    mkdir build && cd build && \
    ../gcc-${GCC_VERSION}/configure \
        --build="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)" \
        --prefix=/opt/gcc-16 --program-suffix=-16 \
        --enable-languages=c,c++ --disable-multilib --disable-bootstrap \
        --enable-default-pie --with-system-zlib --enable-checking=release && \
    make -j"$(nproc)" && \
    make install-strip


FROM ubuntu:26.04

ARG USER_ID=1000
ARG GROUP_ID=1000

# Layer 1: Core system packages, editors, X11/DBus/GL basics (for GUI apps like Typora),
# keychain, Python 3.14 (the 26.04 system Python).
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates curl wget gnupg git sudo zsh tree jq xclip iproute2 zip unzip xz-utils \
        openssh-client keychain \
        vim nano bat micro less \
        dbus dbus-x11 libgl1-mesa-dri libegl-mesa0 adwaita-icon-theme fonts-dejavu \
        python3 python3-venv python3-dev python-is-python3 \
    && rm -rf /var/lib/apt/lists/*

# Layer 2: C/C++ toolchain from the Ubuntu archive - GCC 15 (build-essential), build
# systems, debuggers, analyzers, docs.
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        build-essential cmake ninja-build meson make autoconf automake libtool pkg-config \
        ccache mold gdb valgrind strace ltrace cppcheck bear doxygen graphviz \
    && rm -rf /var/lib/apt/lists/*

# Layer 3: LLVM 23 (latest stable) from apt.llvm.org - Ubuntu 26.04 ships LLVM 21.
# /usr/lib/llvm-23/bin on PATH makes the unversioned names (clang, clangd, lld, ...) v23.
RUN install -d -m 755 /etc/apt/keyrings && \
    curl -fsSL https://apt.llvm.org/llvm-snapshot.gpg.key \
        | gpg --dearmor -o /etc/apt/keyrings/llvm.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/llvm.gpg] http://apt.llvm.org/resolute/ llvm-toolchain-resolute-23 main" \
        > /etc/apt/sources.list.d/llvm.list && \
    apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        clang-23 clangd-23 clang-format-23 clang-tidy-23 clang-tools-23 lld-23 lldb-23 \
        libc++-23-dev libc++abi-23-dev libclang-rt-23-dev && \
    rm -rf /var/lib/apt/lists/*
ENV PATH="/usr/lib/llvm-23/bin:${PATH}"

# Layer 4: GCC 16 from stage 1. ld.so.conf entry so binaries built by it find its newer
# libstdc++ at runtime. Unversioned gcc/g++/cc/c++/... in /usr/local/bin (ahead of
# /usr/bin on PATH) point at GCC 16; GCC 15 stays reachable as gcc-15 / g++-15.
COPY --from=gcc-build /opt/gcc-16 /opt/gcc-16
RUN echo /opt/gcc-16/lib64 > /etc/ld.so.conf.d/gcc-16.conf && ldconfig && \
    for f in /opt/gcc-16/bin/*-16; do \
        b="$(basename "$f")"; \
        case "$b" in x86_64-*) continue ;; esac; \
        ln -s "$f" "/usr/local/bin/$b"; \
        ln -s "$f" "/usr/local/bin/${b%-16}"; \
    done && \
    ln -s /opt/gcc-16/bin/gcc-16 /usr/local/bin/cc

# Layer 5: GitHub CLI (gh) from its official apt repo.
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /etc/apt/keyrings/githubcli-archive-keyring.gpg && \
    chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list && \
    apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends gh && \
    rm -rf /var/lib/apt/lists/*

# Layer 6: Typora (markdown editor, GUI over X11). Direct CDN download rather than the
# typora.io/linux apt repo, whose origin intermittently 526s behind Cloudflare.
# The .deb does not declare its Electron runtime libs, so they are listed explicitly;
# gsettings-desktop-schemas keeps GTK's open/save dialogs from aborting.
# The /usr/local/bin/typora wrapper (ahead of /usr/bin on PATH) adds --no-sandbox:
# Chromium's sandbox must create PID/network namespaces, which Docker's default seccomp
# profile forbids. Allowing that (seccomp=unconfined / CAP_SYS_ADMIN) would weaken the
# whole container, so only Typora runs unsandboxed, with the container as its boundary.
RUN curl -fsSL -o /tmp/typora.deb \
        https://download.typora.io/linux/typora_1.13.6_amd64.deb && \
    apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        /tmp/typora.deb \
        libnss3 libnspr4 libgtk-3-0t64 libatk1.0-0t64 libatk-bridge2.0-0t64 libatspi2.0-0t64 \
        libcups2t64 libasound2t64 libxkbcommon0 libxcomposite1 libxdamage1 libxfixes3 \
        libxrandr2 gsettings-desktop-schemas && \
    rm -f /tmp/typora.deb && \
    rm -rf /var/lib/apt/lists/* && \
    printf '#!/bin/sh\nexec /usr/share/typora/Typora --no-sandbox "$@"\n' > /usr/local/bin/typora && \
    chmod 755 /usr/local/bin/typora

# Layer 7: uv system-wide, plus conan as an image-managed uv tool (upgrade by rebuilding).
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin UV_NO_MODIFY_PATH=1 sh && \
    UV_TOOL_DIR=/opt/uv-tools UV_TOOL_BIN_DIR=/usr/local/bin \
        uv tool install --python /usr/bin/python3 conan

# Layer 8: Free UID 1000 (Ubuntu base image's built-in `ubuntu` user) and create devuser.
# Using host UID 1000 means no chown of bind-mounted host directories needed.
RUN userdel -r ubuntu 2>/dev/null || true && \
    groupadd -g $GROUP_ID devgroup && \
    useradd -m -u $USER_ID -g $GROUP_ID devuser && \
    chsh -s /usr/bin/zsh devuser && \
    usermod -aG sudo devuser && \
    echo "devuser ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/devuser && \
    chmod 0440 /etc/sudoers.d/devuser

# Layer 9: vcpkg, full clone (its versioning/baselines need history), owned by devuser
# so `git pull` + re-bootstrap work without sudo.
RUN git clone https://github.com/microsoft/vcpkg.git /opt/vcpkg && \
    /opt/vcpkg/bootstrap-vcpkg.sh -disableMetrics && \
    chown -R $USER_ID:$GROUP_ID /opt/vcpkg
ENV VCPKG_ROOT=/opt/vcpkg \
    VCPKG_DISABLE_METRICS=1 \
    PATH="/opt/vcpkg:${PATH}"

# Layer 10: dbus machine-id (some GUI apps complain without it).
# Note: --ensure errors on Ubuntu's empty /etc/machine-id, so write directly.
RUN dbus-uuidgen > /etc/machine-id && \
    ln -sf /etc/machine-id /var/lib/dbus/machine-id

# Claude Code managed settings: root-owned, so neither Claude nor user/project settings can
# override them. Denies Claude's file tools on ~/.ssh - a guard against accidental reads,
# not a hard boundary (see README "Claude Code"). The dir is created first because
# COPY --chmod would apply 644 to an implicitly created parent too, making it untraversable.
RUN install -d -m 755 /etc/claude-code
COPY --chmod=644 claude-managed-settings.json /etc/claude-code/managed-settings.json

USER devuser
WORKDIR /home/devuser

# Layer 11: oh-my-zsh, plugins, .zshrc.
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended && \
    git clone https://github.com/zsh-users/zsh-autosuggestions .oh-my-zsh/custom/plugins/zsh-autosuggestions && \
    git clone https://github.com/zsh-users/zsh-syntax-highlighting .oh-my-zsh/custom/plugins/zsh-syntax-highlighting && \
    sed -i 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' .zshrc && \
    { \
      echo ''; \
      echo '# --- GeneralDevDocker additions ---'; \
      echo 'export NO_AT_BRIDGE=1'; \
      echo 'export LIBGL_ALWAYS_SOFTWARE=1'; \
      echo '# docker exec gives a colorless TERM / no COLORTERM; advertise real capability for TUIs'; \
      echo 'export COLORTERM="${COLORTERM:-truecolor}"'; \
      echo '[[ "$TERM" == "xterm" || "$TERM" == "dumb" ]] && export TERM=xterm-256color'; \
      echo 'export PATH="$HOME/.local/bin:$HOME/.claude/local/bin:$PATH"'; \
      echo "alias bat='batcat'"; \
      echo 'export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-$(id -u)}"'; \
      echo 'mkdir -p "$XDG_RUNTIME_DIR" 2>/dev/null && chmod 700 "$XDG_RUNTIME_DIR" 2>/dev/null'; \
      echo '_keys=(~/.ssh/id_*(N)); _keys=(${_keys:#*.pub})'; \
      echo '(( ${#_keys[@]} )) && eval "$(keychain --eval --quiet "${_keys[@]}" 2>/dev/null)"'; \
      echo '(( ${#_keys[@]} )) || {'; \
      echo '  print -r -- "No SSH key in ~/.ssh. Either:"'; \
      echo '  print -r -- "  - generate a dedicated key for this container:  generate-ssh-key"'; \
      echo '  print -r -- "  - or import one from the host via ~/fast_share:  import-ssh-keys-from-fastshare <name>"'; \
      echo '}'; \
      echo 'unset _keys'; \
    } >> .zshrc

# Layer 12: Claude Code CLI (native installer, in the home volume so self-updates persist).
# Login and configuration are done by the user inside the container.
RUN curl -fsSL https://claude.ai/install.sh | bash

ENV PATH="/home/devuser/.local/bin:/home/devuser/.claude/local/bin:${PATH}"

COPY generate-ssh-key.sh /usr/local/bin/generate-ssh-key
COPY import-ssh-keys-from-fastshare.sh /usr/local/bin/import-ssh-keys-from-fastshare

# Entrypoint applies git identity + editor defaults on every container start (so .env
# changes take effect without rebuilding the image or wiping the home volume).
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
ENTRYPOINT ["entrypoint.sh"]
CMD ["tail", "-f", "/dev/null"]
