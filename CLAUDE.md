# DevDockers - project rules

## Dockerfile layer order (build cache)

Docker rebuilds a changed layer and every layer below it. The heavy layers (WebStorm, Playwright, LLVM, Typora, the C/C++ toolchain) cost GBs of downloads, so both Dockerfiles are ordered so that routine edits rebuild only the cheap tail:

```
stages:  big downloads/builds, cached on their own (gcc-build, vcpkg, webstorm)
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
- A new big download (archive, git clone, source build) gets its own stage plus `COPY --from=...`, like `gcc-build`, `vcpkg` and `webstorm`.
- Declare an `ARG` right before its first use: every `RUN` after an `ARG` has it in its cache key.
- oh-my-zsh, Claude Code and (FullStack) uv install into the home volume, which hides the image's copy after the volume's first start. They only seed fresh volumes, so they sit above `extras` and rarely rebuild.
- Often-edited content (the zshrc block, config `COPY`s, entrypoint) stays at the very end.
- Before any edit that rebuilds a heavy layer (touching `base`, `SHELL`/top `ENV`, a heavy layer's version or command), say so and why, and prefer a placement that avoids it.
- Use `apt-get`, not `apt`: `apt` has no stable CLI for scripts (hadolint DL3027).
