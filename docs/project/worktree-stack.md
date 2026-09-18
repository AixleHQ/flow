# Running a second stack from a git worktree

For agents and humans reviewing a branch in a `git worktree` while the default
stack in the main checkout keeps running.

By default every checkout brings up the **same** stack: the Compose network is
pinned to `app_default`, the image is tagged `web`, and Traefik, Temporal and the
OTLP collector publish fixed host ports. Two checkouts started that way do not
run side by side — they fight. The second one either fails to bind a port, or
worse, silently resolves `db`, `redis` and `web` to the *first* stack's
containers, so a branch appears to pass against the wrong database.

Everything that makes a stack global is now a variable with the old value as its
default. Set them and the worktree gets its own network, its own Postgres, its
own agent containers; leave them unset and nothing changes.

## Procedure

1. Create the worktree outside the main checkout, then symlink `node_modules`
   from it — the tree is mounted into the container and yarn's state file has to
   resolve:

   ```bash
   ln -s ../../app/node_modules node_modules   # relative, from the worktree root
   ```

2. Write a `.env` **in the worktree root**. Compose only ever reads `.env`, never
   `.env.development`; Rails' dotenv reads both, so one file covers both sides.
   `.env.example` carries this block ready to uncomment:

   ```bash
   DOCKER_NETWORK=trevally_net
   WEB_IMAGE=web-trevally
   PORT=4010
   VITE_RUBY_PORT=4011
   MCP_PORT=4012
   TEMPORAL_HOST_PORT=7333
   TEMPORAL_UI_HOST_PORT=8180
   OTLP_HOST_PORT=4418
   HTTP_HOST_PORT=8081
   HTTPS_HOST_PORT=8444
   TRAEFIK_DASHBOARD_HOST_PORT=8091
   TRAEFIK_HTTP_BASE=http://localhost:8081
   ```

3. Bring it up and check what Compose resolved before trusting it:

   ```bash
   docker compose config | grep -E '^name:|published:|name: .*_net'
   docker compose up -d
   ```

4. Tear down with `docker compose down -v`. The volumes are named after the
   Compose project (the worktree directory), so `-v` drops this stack's database
   and never the main one's.

## What each variable protects

| Variable | Default | What shares state without it |
|---|---|---|
| `DOCKER_NETWORK` | `app_default` | `db`, `redis` and `web` resolve to the other stack; agent containers join it too, via `Settings.docker.network` |
| `WEB_IMAGE` | `web` | A build in the worktree overwrites the image the main stack runs |
| `PORT`, `VITE_RUBY_PORT`, `MCP_PORT` | `4000`–`4002` | Port bind conflict |
| `TEMPORAL_HOST_PORT`, `TEMPORAL_UI_HOST_PORT` | `7233`, `8080` | Port bind conflict (in-network traffic still uses `temporal:7233`) |
| `OTLP_HOST_PORT` | `4318` | Port bind conflict |
| `HTTP_HOST_PORT`, `HTTPS_HOST_PORT`, `TRAEFIK_DASHBOARD_HOST_PORT` | `80`, `443`, `8090` | Port bind conflict |
| `TRAEFIK_HTTP_BASE` | `http://localhost` | Terminal / file-watcher / IDE URLs point at the other stack's Traefik |

## Things that bite

- **Tests can now run in parallel — but only because of this.** CLAUDE.md bans
  two concurrent backend test runs *that share a Postgres*. An isolated stack has
  its own `db` container and its own `aixle_test-N` databases, so a suite here
  does not touch the main checkout's. Note that the `make` flock lives at
  `tmp/.rails-test.lock`, which is repo-relative: it does **not** serialize a
  worktree run against the main checkout. Isolation is what makes that safe, not
  the lock.
- **Google sign-in will not work.** The OAuth redirect URI is registered for
  `:4000` only, so a stack on another port always fails with
  `redirect_uri_mismatch`. Sign in as a seeded local user instead.
- **Both Traefiks watch the same Docker socket**, so each one sees the other
  stack's containers and logs that it cannot reach them. Harmless: routers are
  named per network (`<network>-api`) and per session (`terminal-<route_token>`),
  so nothing collides, and each Traefik only resolves addresses on its own
  network.
- **The worker does not autoreload.** Changing container-launch code needs
  `docker compose restart worker`.
- **Never kill containers by image.** With `WEB_IMAGE` set the filter is less
  ambiguous, but `docker rm -f $(docker ps -q --filter ancestor=web)` still
  reaches the other stack. Kill by container name.
