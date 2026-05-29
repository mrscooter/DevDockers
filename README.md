# DevDockers

Containerized, throwaway dev environments - one per stack. Each bundles an IDE
plus the runtimes/tooling for its stack, so all work (including AI agents let
loose inside) stays isolated from the host. Spin up, work, throw away.

One image per stack on purpose - not a single mega-image. A web project should
not drag a C++ toolchain (and four JetBrains IDEs) into its container. Shared
scaffolding stays light through copy where it is cheap; a common base image gets
extracted only once a third stack makes the duplication hurt.

## What's here

| Dir | Role |
|---|---|
| [`FullStackWebDevDocker/`](FullStackWebDevDocker/) | Web stack: WebStorm + Python 3.12/uv + Node 20 + Playwright. Serves any Python-backend + Node-frontend + Postgres project. |
| [`shared-db/`](shared-db/) | One shared PostgreSQL 16, used by all web dev-dockers. |

(The C++ sibling, `CLionDevDocker`, lives outside this repo at `~/Tools/`.)

## shared-db

Postgres runs **once**, here, as its own project - not inside each dev-docker.
Every web dev-docker connects to it at `localhost:5433`. That decoupling is what
lets several worktrees run at the same time (each uses its own *database* on the
one server) without fighting over a port. Start it before any dev-docker; see
[`shared-db/README.md`](shared-db/README.md).

## Start here

1. [`shared-db/`](shared-db/) - bring the database up once.
2. [`FullStackWebDevDocker/`](FullStackWebDevDocker/) - its README has the full
   ordered setup-from-scratch.

Per-machine `.env` files and `context_restore-*.md` snapshots are git-ignored;
`.env.example` templates are tracked.
