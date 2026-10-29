# Base image pinned by digest: the bare tag is republished every week or two, and each
# new digest silently rebuilds every layer. Bump deliberately, see ../CLAUDE.md.
ARG BASE_IMAGE=ubuntu:26.04@sha256:6a06111c3b0a8600feadb270aec771dc239bf407b25625f93f44ab00e11f4d3c

# Stage 1: GCC from source. Ubuntu 26.04 ships GCC 15 as default and only a pre-release
# snapshot of gcc-16, so the latest stable GCC is built here (C++26 reflection/contracts).
# Installed to /opt/gcc-16 and copied into the final image; this stage is layer-cached.
FROM ${BASE_IMAGE} AS gcc-build

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


# Final image. Layers are ordered so routine edits rebuild only the cheap tail - read
# "Dockerfile layer order" in ../CLAUDE.md before adding or moving anything.
FROM ${BASE_IMAGE}

# Fail a RUN when any command in a pipe fails, not just the last one: a `curl | bash`
# installer whose download failed would otherwise build a layer without the tool.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# UTF-8 locale: without it zsh measures non-ASCII prompt glyphs (e.g. a nerd-font
# PROMPT_PREFIX) in bytes, misplaces the cursor on redraw and leaves stale text.
ENV LANG=C.UTF-8

# base apt: what later layers need while building (curl, gnupg, git, sudo, zsh, dbus)
# plus stable system plumbing, X11/DBus/GL basics for GUI apps and Python 3.14 (the
# 26.04 system Python). zip/unzip are vcpkg runtime deps. Editing this list rebuilds
# everything below; new packages go to the extras layer.
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg git sudo zsh zip unzip xz-utils \
        dbus dbus-x11 libgl1-mesa-dri libegl-mesa0 adwaita-icon-theme fonts-dejavu \
        python3 python3-venv python3-dev python-is-python3 \
    && rm -rf /var/lib/apt/lists/*

# C/C++ toolchain from the Ubuntu archive - GCC 15 (build-essential), build systems,
# debuggers, analyzers, docs. New tools go to the extras layer, not here.
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        build-essential cmake ninja-build meson make autoconf automake libtool pkg-config \
        ccache mold gdb valgrind strace ltrace cppcheck bear doxygen graphviz \
    && rm -rf /var/lib/apt/lists/*

# LLVM 23 (latest stable) from apt.llvm.org - Ubuntu 26.04 ships LLVM 21.
# /usr/lib/llvm-23/bin on PATH makes the unversioned names (clang, clangd, lld, ...) v23.
# llvm-23 brings the llvm-* tools: llvm-symbolizer (sanitizer file:line), llvm-cov /
# llvm-profdata (clang coverage), llvm-ar (LTO), ...
RUN install -d -m 755 /etc/apt/keyrings && \
    curl -fsSL https://apt.llvm.org/llvm-snapshot.gpg.key \
        | gpg --dearmor -o /etc/apt/keyrings/llvm.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/llvm.gpg] http://apt.llvm.org/resolute/ llvm-toolchain-resolute-23 main" \
        > /etc/apt/sources.list.d/llvm.list && \
    apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        clang-23 clangd-23 clang-format-23 clang-tidy-23 clang-tools-23 lld-23 lldb-23 llvm-23 \
        libc++-23-dev libc++abi-23-dev libclang-rt-23-dev && \
    rm -rf /var/lib/apt/lists/*
ENV PATH="/usr/lib/llvm-23/bin:${PATH}"

# GCC 16 from stage 1. ld.so.conf entry so binaries built by it find its newer
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

# GitHub CLI (gh) from its official apt repo.
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /etc/apt/keyrings/githubcli-archive-keyring.gpg && \
    chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list && \
    apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends gh && \
    rm -rf /var/lib/apt/lists/*

# uv system-wide. Python tools such as conan are per user (`uv tool install conan`, into
# ~/.local in the home volume), so they persist and upgrade without a rebuild.
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin UV_NO_MODIFY_PATH=1 sh

# Free UID 1000 (Ubuntu base image's built-in `ubuntu` user) and create devuser.
# Using host UID 1000 means no chown of bind-mounted host directories needed.
# The ARGs are declared here, not at the top: every RUN after an ARG has it in its
# cache key, so a different USER_ID would otherwise rebuild the whole image.
ARG USER_ID=1000
ARG GROUP_ID=1000
RUN userdel -r ubuntu 2>/dev/null || true && \
    groupadd -g $GROUP_ID devgroup && \
    useradd -m -u $USER_ID -g $GROUP_ID devuser && \
    chsh -s /usr/bin/zsh devuser && \
    usermod -aG sudo devuser && \
    echo "devuser ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/devuser && \
    chmod 0440 /etc/sudoers.d/devuser

# dbus machine-id (some GUI apps complain without it).
# Note: --ensure errors on Ubuntu's empty /etc/machine-id, so write directly.
RUN dbus-uuidgen > /etc/machine-id && \
    ln -sf /etc/machine-id /var/lib/dbus/machine-id

USER devuser
WORKDIR /home/devuser

# oh-my-zsh, plugins. This and Claude Code below install into the home volume, which
# hides the image's copy after its first start: they only seed a fresh volume, so
# rebuilding them buys nothing and they sit above the often-edited layers.
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended && \
    git clone https://github.com/zsh-users/zsh-autosuggestions .oh-my-zsh/custom/plugins/zsh-autosuggestions && \
    git clone https://github.com/zsh-users/zsh-syntax-highlighting .oh-my-zsh/custom/plugins/zsh-syntax-highlighting && \
    sed -i 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' .zshrc

# Claude Code CLI (native installer, in the home volume so self-updates persist).
# Login and configuration are done by the user inside the container.
RUN curl -fsSL https://claude.ai/install.sh | bash

ENV PATH="/home/devuser/.local/bin:/home/devuser/.claude/local/bin:${PATH}"

USER root

# extras apt: leaf packages no layer above needs while building - editors, CLI tools.
# New packages go here by default: editing this list rebuilds only the cheap layers below.
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        wget tree jq xclip iproute2 openssh-client \
        vim nano bat micro less \
    && rm -rf /var/lib/apt/lists/*

# Claude Code managed settings: root-owned, so user/project settings cannot override them
# (root can, and devuser has passwordless sudo). Denies Claude's file tools on ~/.ssh - a
# guard against accidental reads of a key put there by hand, not a hard boundary (see
# README "Claude Code"). The dir is created first because COPY --chmod would apply 644
# to an implicitly created parent too, making it untraversable.
RUN install -d -m 755 /etc/claude-code
COPY --chmod=644 claude-managed-settings.json /etc/claude-code/managed-settings.json

# Shell setup in the system-wide /etc/zsh/zshrc (sourced before ~/.zshrc), not in the
# home volume, so image rebuilds reach existing volumes too.
RUN { \
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
      echo '# Optional PROMPT_PREFIX (.env): prepended once, before the first prompt, because the'; \
      echo '# oh-my-zsh theme in ~/.zshrc sets PROMPT only after this file has run.'; \
      echo 'if [[ -n "$PROMPT_PREFIX" ]]; then'; \
      echo '  autoload -Uz add-zsh-hook'; \
      echo '  _prompt_prefix() { PROMPT="$PROMPT_PREFIX $PROMPT"; add-zsh-hook -d precmd _prompt_prefix; }'; \
      echo '  add-zsh-hook precmd _prompt_prefix'; \
      echo 'fi'; \
    } >> /etc/zsh/zshrc

# Entrypoint applies git identity + editor defaults on every container start (so .env
# changes take effect without rebuilding the image or wiping the home volume).
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

USER devuser
ENTRYPOINT ["entrypoint.sh"]
CMD ["tail", "-f", "/dev/null"]
