# shared-db

A single standalone PostgreSQL 16 instance, shared by every [FullStackWebDevDocker](../FullStackWebDevDocker/) worktree dev-docker.

## Why it is separate

Each worktree dev-docker runs on host networking, so if every one carried its own Postgres they would all fight over the host's port 5432 and could not run at the same time. Instead there is one Postgres here, started once, and every worktree connects to it at `localhost:5433`. Worktrees stay isolated by using a different *database* (not a different server) on this one instance.

```
                 shared-db (this project)
                 Postgres on 127.0.0.1:5433
                          |
      ┌───────────────────┼───────────────────┐
  dev-docker A        dev-docker B        dev-docker C   (worktrees)
  db: app_a           db: app_b           db: app_c
```

## Setup

```bash
cp .env.example .env          # adjust only if you want non-default creds/port
docker compose up -d
docker compose ps             # postgres should be Up (healthy)
```

`restart: unless-stopped` keeps it running across reboots, independent of any dev-docker. The data lives in the named volume `shared-pg-data` and survives `docker compose down`; only `docker compose down -v` wipes it.

## Per-worktree databases

The image creates one database (`POSTGRES_DB`) at first init. Create each additional worktree's database against the running server:

```bash
createdb -h localhost -p 5433 -U admin app_b      # password: devPass77
# or from inside a dev-docker (PG* vars are already set there):
createdb app_b
```

Then point that worktree's `FullStackWebDevDocker/.env` at it via `POSTGRES_DB=app_b`.

## Connection details

| | |
|--|--|
| Host | `localhost` (bound to 127.0.0.1 only) |
| Port | `5433` (host side; container side is 5432) |
| User | `admin` |
| Password | `devPass77` |

## Port conflicts

The default `5433` avoids a native host Postgres on 5432. If 5433 is also in use, `docker compose up` fails loudly with `port is already allocated`. Check what holds it, then bump `PG_HOST_PORT` in `.env` and update each dev-docker's `.env` to match:

```bash
ss -ltn '( sport = :5433 )'
```

> The values in this project's `.env` (`POSTGRES_USER`, `POSTGRES_PASSWORD`, `PG_HOST_PORT`) must match the same vars in every `FullStackWebDevDocker/.env`, or the dev-dockers cannot authenticate / connect.
