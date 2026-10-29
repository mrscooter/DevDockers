# DevDockers - project rules

## Dockerfile layer order (build cache)

Docker rebuilds a changed layer and every layer below it. The heavy layers (WebStorm, LLVM, the C/C++ toolchain, GCC 16, Playwright's OS libs) cost GBs of downloads, so both Dockerfiles are ordered so that routine edits rebuild only the cheap tail:

```
stages:  big downloads/builds, cached on their own (gcc-build, webstorm)
final:   SHELL, ENV LANG
         base apt         - what later layers need while building + stable plumbing
         heavy layers     - least-changed first; COPY --from the stages
         small leaf installs from third-party repos/installers (gh, psql, uv)
         ARG USER_ID/GROUP_ID + user creation, machine-id
         devuser: oh-my-zsh, Claude Code (+ uv)
         extras apt       - leaf packages
         config COPYs, /etc/zsh/zshrc block, entrypoint
```

- A new apt package goes into the `extras` layer, unless a layer above `extras` needs it while building. Only then does it go into `base`, which means a full rebuild.
- Only build-time needs count for placement. A package a heavy app needs only at runtime does not have to sit above that app.
- Keep the two generic apt layers (`base`, `extras`); don't add one apt layer per tool. Packages from a third-party apt repo stay in their own layer.
- A new big download (archive, git clone, source build) gets its own stage plus `COPY --from=...`, like `gcc-build` and `webstorm`.
- Declare an `ARG` right before its first use: every `RUN` after an `ARG` has it in its cache key.
- oh-my-zsh, Claude Code and (FullStack) uv install into the home volume, which hides the image's copy after the volume's first start. They only seed fresh volumes, so they sit above `extras` and rarely rebuild.
- Often-edited content (the zshrc block, config `COPY`s, entrypoint) stays at the very end.
- Before any edit that rebuilds a heavy layer (touching `base`, `SHELL`/top `ENV`, a heavy layer's version or command), say so and why, and prefer a placement that avoids it.
- Use `apt-get`, not `apt`: `apt` has no stable CLI for scripts (hadolint DL3027).

## Image vs project vs home volume

- Image: what needs root or system paths and serves every project - apt packages, system toolchains, GUI apps, OS libs a project tool needs (e.g. `playwright install-deps`).
- Project: anything a project manifest pins - npm packages and their Playwright browsers, Python deps and interpreter (uv), conan/vcpkg packages. The project's own setup (e.g. `make setup`) installs it.
- Home volume (`/home/devuser`, survives recreates): per-user tools the user installs and updates without a rebuild - uv tools (conan), the vcpkg clone (General), Claude Code, oh-my-zsh.
- Anything installed outside `~` inside a running container (e.g. `sudo apt install`) is lost on the next recreate, and `up.sh` recreates after every image change. An apt package worth keeping goes into `extras`.
- Never point a project cache at an image path (e.g. `PLAYWRIGHT_BROWSERS_PATH=/opt/...`): installs there land in the container layer and are lost on every recreate.
- GeneralDevDocker ships no GUI app but keeps full X11 support (X socket mount, `xhost-setup.sh`, `DISPLAY`, dbus-x11, GL libs, machine-id) on purpose: the user installs GUI apps by hand inside the container. Don't remove the X11 support as unused, and don't bake GUI apps into the image unless asked.

## Base image pinning

Both Dockerfiles take the base from `ARG BASE_IMAGE=ubuntu:<tag>@sha256:<digest>`, used by every stage. A bare tag is looked up on Docker Hub at every build and gets republished every week or two; each new digest silently rebuilds every layer, including the ~9 min GCC build. Bump the digest deliberately (it is a full rebuild), in both Dockerfiles at once so they keep sharing one base: `docker buildx imagetools inspect ubuntu:26.04 | grep -m1 Digest`.
