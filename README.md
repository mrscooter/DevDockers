# DevDockers

Containerized, throwaway dev environments - one per stack. Each bundles the runtimes/tooling for its stack, but no IDE (installed by hand per container, in its home volume), so all work (including AI agents let loose inside) stays isolated from the host. Spin up, work, throw away.

One image per stack on purpose - not a single mega-image. A web project should not drag a C++ toolchain into its container. Shared scaffolding stays light: the host-side scripts (`up.sh`, `zsh-into-docker-container.sh` and their helpers) and the containers' `entrypoint.sh` live once in `shared-scripts/` (host-side ones symlinked into each dev-docker, the entrypoint copied into each image), the rest is copied where it is cheap; a common base image gets extracted only once a third stack makes the duplication hurt.

## What's here

| Dir | Role |
|---|---|
| [`FullStackWebDevDocker/`](FullStackWebDevDocker/) | Web stack: Python 3.14/uv + Node 24 + Playwright's OS libs, no IDE. Serves any Python-backend + Node-frontend + Postgres project. |
| [`shared-db/`](shared-db/) | One shared PostgreSQL 16, used by all web dev-dockers. |
| [`GeneralDevDocker/`](GeneralDevDocker/) | General Linux box for Python + C/C++ experiments: GCC 16 + Clang 23 + Python 3.14/uv, no IDE. Stricter isolation than FullStack: bridge network instead of host networking, no host project mount. Standalone - no shared-db. |
| [`shared-scripts/`](shared-scripts/) | Scripts shared by the dev-dockers. Host-side, symlinked into each one's dir: `up.sh`, `zsh-into-docker-container.sh`, `ssh-agent-paths.sh`, `xhost-setup.sh`; they `cd` to the symlink's dir, so they act on that dev-docker's `compose.yaml` / `.env`. Run them through the symlinks, not from here. In-image: `entrypoint.sh`, copied into both images through the `shared` build context in each `compose.yaml`. |

## shared-db

Postgres runs **once**, here, as its own project - not inside each dev-docker. Every web dev-docker connects to it at `localhost:5433`. That decoupling is what lets several worktrees run at the same time (each uses its own *database* on the one server) without fighting over a port. Start it before any dev-docker; see [`shared-db/README.md`](shared-db/README.md).

## Start here

1. [`shared-db/`](shared-db/) - bring the database up once.
2. [`FullStackWebDevDocker/`](FullStackWebDevDocker/) - its README has the full ordered setup-from-scratch.

[`GeneralDevDocker/`](GeneralDevDocker/) is independent of both - its README has its own setup.

Per-machine `.env` files and `context_restore-*.md` snapshots are git-ignored; `.env.example` templates are tracked.
