# omnigent-deploy — Omnigent, standalone

Two independent services, not one:

- **Holodeck** (`../holodeck/`) — a FastAPI control-plane process. Runs as
  a plain `python3 -m holodeck.main`, not a container, per
  `setup-omnigent-poc-box.sh`.
- **Omnigent** (here) — a Docker container. Talks to Holodeck over HTTP
  (`HOLODECK_URL`); Holodeck knows nothing about how Omnigent is deployed.

Both can run on the same VM (that's the current plan — see
`../../docs/10-omnigent-gce-deployment.md`), but this folder deliberately
has no path that reaches into `../holodeck/` except one clearly-marked
script (`scripts/sync-wheel.sh`). Everything else here — the Dockerfile,
the compose file — only ever looks at `./wheels/*.whl`, a local staging
directory. Swapping Holodeck for a different harness later means writing a
different sync script (or none, if the new harness hands you a wheel
directly); the Dockerfile doesn't change.

## Layout

```
omnigent-deploy/
  omnigent/
    Dockerfile           bakes whatever wheel is in ../wheels/ + psycopg2-binary
                          into the upstream Omnigent image
    docker-compose.yml    omnigent + a local postgres + caddy (profile "tls")
    Caddyfile              reverse proxy, cert auto-issued for a *.sslip.io host
    .env.example           every required variable, documented in place
  wheels/                 sandbox-provider wheel(s) go here before building —
                          empty by default; populated by sync-wheel.sh
  scripts/
    sync-wheel.sh          the ONE script that knows Holodeck exists — copies
                          (optionally rebuilds) its provider wheel into ./wheels/
    pull-env.sh            CLOUD=aws|gcp|local — writes omnigent/.env from a
                          cloud secret store (or .env.example for local/first bring-up)
    provision-omnigent-aws.sh   builds + starts everything on an AWS EC2 box
    provision-omnigent-gcp.sh   the GCE equivalent — UNVERIFIED, see its header
```

## Running it on EC2/GCE

```bash
# 1. pull in the current Holodeck sandbox-provider wheel
./scripts/sync-wheel.sh

# 2. get the env bundle — CLOUD=local for a first run before any cloud secret exists
CLOUD=local ./scripts/pull-env.sh
# edit omnigent/.env, filling in at least:
#   OMNIGENT_ACCOUNTS_COOKIE_SECRET (openssl rand -hex 32)
#   HOLODECK_TOKEN (must match the control plane's own)
#   HOLODECK_APP, ANTHROPIC_API_KEY, POSTGRES_PASSWORD

# 3. build, start, wire up TLS + the public hostname
HOLODECK_TOKEN=<same value> ./scripts/provision-omnigent-aws.sh
```

First visit to the printed URL shows a Create-admin form (fresh Postgres,
no admin yet) — set your own username/password there.

**Security group**: inbound 80/tcp (Caddy's Let's Encrypt challenge) and
443/tcp (the UI) need to be open. Port 8099 (the control plane) stays
internal — Omnigent reaches it over `localhost` when colocated on the same
box.

## Running it locally (Docker Desktop)

No TLS, no public IP needed — this is enough to confirm the image builds,
the wheel/monkeypatch loads without error, and the accounts-auth UI comes
up:

```bash
./scripts/sync-wheel.sh
CLOUD=local ./scripts/pull-env.sh
```

Edit `omnigent/.env`:
- `OMNIGENT_ACCOUNTS_BASE_URL=http://localhost:8000` (plain http is fine
  for local dev — the code only requires https for the `__Host-` secure
  cookie prefix, which local dev deliberately skips)
- `OMNIGENT_SANDBOX_SERVER_URL` — **must be non-empty**, even for a UI-only
  test (`http://localhost:8000` is fine) — this is validated at server
  boot, not lazily, so an empty value crashes the container before it
  serves anything
- `HOLODECK_TOKEN` / `HOLODECK_APP` — any placeholder value works if you're
  not also running the control plane locally
- `POSTGRES_PASSWORD` — any value
- `ANTHROPIC_API_KEY` — a real key only if you want to get as far as an
  actual agent session, not needed just to see the UI

Then, from `omnigent/`:

```bash
docker compose up -d postgres omnigent   # note: no --profile tls — Caddy is skipped
docker compose logs -f omnigent          # watch it boot
```

Visit `http://localhost:8000` — you should land on the Create-admin form.
If you also want the full loop (a host actually registering), run
Holodeck's control plane locally too (`cd ../../holodeck/control-plane &&
python3 -m holodeck.main`, per that repo's own README) and point
`HOLODECK_URL` at it.

## Updating the sandbox-provider wheel

See `../docs/10-omnigent-gce-deployment.md`'s "Updating the sandbox
provider" section for the full walkthrough (short version: bump the
version in the provider's `pyproject.toml`, `./scripts/sync-wheel.sh
--build`, then `docker compose build && docker compose up -d
--force-recreate omnigent` — editing the provider's source alone changes
nothing running until all of those steps happen).

## Switching to GCP later

1. Write the GCE equivalent of `setup-omnigent-poc-box.sh` (doesn't exist yet).
2. Create the equivalent secret in GCP Secret Manager (same JSON shape as
   the AWS one — see `.env.example`).
3. `CLOUD=gcp ./scripts/pull-env.sh` then `./scripts/provision-omnigent-gcp.sh`.

`Dockerfile` and `docker-compose.yml` are shared, unmodified, between both
clouds — only the box-setup and secret-fetch steps differ.
