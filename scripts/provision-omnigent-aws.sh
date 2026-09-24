#!/usr/bin/env bash
# provision-omnigent-aws.sh — brings up Omnigent (Docker, behind Caddy for
# TLS) on a box that already has Docker and a running Holodeck control
# plane on :8099 (setup-omnigent-poc-box.sh, reference-materials/root-docs/
# — a SEPARATE clone/folder from this one; this script never assumes
# anything about its internals beyond "port 8099 answers").
#
# This is the AWS half of the CLOUD=aws/gcp split. provision-omnigent-gcp.sh
# is the (currently UNVERIFIED) GCE counterpart — same Dockerfile and
# docker-compose.yml, only the box-setup commands below differ.
#
# Required env vars:
#   HOLODECK_TOKEN   must be the exact same value the control plane was
#                    started with — the shared secret between Omnigent and
#                    the control plane, independent of network topology.
# Optional:
#   OMNIGENT_DEPLOY_DIR   path to this cloned repo's `omnigent/` subfolder
#                         (default: the location of this script's own
#                         checkout, resolved automatically)
set -euo pipefail
: "${HOLODECK_TOKEN:?set HOLODECK_TOKEN — must match the control plane's}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="${OMNIGENT_DEPLOY_DIR:-$HERE/../omnigent}"

log() { printf '\033[34m[omnigent-aws]\033[0m %s\n' "$*"; }

command -v docker >/dev/null 2>&1 || { echo "docker not found — install it first" >&2; exit 1; }
if ! curl -sf http://localhost:8099/healthz >/dev/null; then
  log "WARNING: nothing answering on :8099 — Omnigent will still start, but a"
  log "  managed session will fail until the Holodeck control plane is up"
fi

# ---- 1. secrets ------------------------------------------------------------
if [[ ! -f "$DEPLOY_DIR/.env" ]]; then
  echo "no .env at $DEPLOY_DIR/.env — run scripts/pull-env.sh (CLOUD=aws or CLOUD=local) first" >&2
  exit 1
fi
grep -q '^HOLODECK_TOKEN=$' "$DEPLOY_DIR/.env" && \
  sed -i.bak "s#^HOLODECK_TOKEN=.*#HOLODECK_TOKEN=${HOLODECK_TOKEN}#" "$DEPLOY_DIR/.env"

# ---- 2. the sandbox-provider wheel ------------------------------------------
if ! ls "$HERE/../wheels"/*.whl >/dev/null 2>&1; then
  log "no wheel in ../wheels/ yet — running sync-wheel.sh"
  "$HERE/sync-wheel.sh"
fi

# ---- 3. public hostname for TLS (sslip.io — no domain needed for the POC) --
PUBLIC_IP="$(curl -sf https://checkip.amazonaws.com)"
PUBLIC_HOST="${PUBLIC_IP}.sslip.io"
log "public host for this box: $PUBLIC_HOST"
sed -i.bak \
  -e "s#^OMNIGENT_ACCOUNTS_BASE_URL=.*#OMNIGENT_ACCOUNTS_BASE_URL=https://${PUBLIC_HOST}#" \
  -e "s#^OMNIGENT_SANDBOX_SERVER_URL=.*#OMNIGENT_SANDBOX_SERVER_URL=https://${PUBLIC_HOST}#" \
  -e "s#^OMNIGENT_PUBLIC_HOST=.*#OMNIGENT_PUBLIC_HOST=${PUBLIC_HOST}#" \
  "$DEPLOY_DIR/.env"

# ---- 4. build + run ---------------------------------------------------------
log "building the Omnigent image (wheel + psycopg2-binary baked in — see Dockerfile)"
(cd "$DEPLOY_DIR" && docker compose build)
log "starting omnigent + postgres + caddy (--profile tls pulls Caddy in; local runs skip it)"
(cd "$DEPLOY_DIR" && docker compose --profile tls up -d)

log "waiting for Omnigent to report healthy (up to ~60s)"
healthy=0
for _ in $(seq 1 30); do
  if docker compose -f "$DEPLOY_DIR/docker-compose.yml" ps omnigent --format json 2>/dev/null \
      | grep -q '"Health":"healthy"'; then
    healthy=1
    break
  fi
  sleep 2
done
[[ "$healthy" -eq 1 ]] && log "omnigent is healthy" || log "omnigent not healthy yet — check: docker compose -f $DEPLOY_DIR/docker-compose.yml logs omnigent"

log "done. Visit https://${PUBLIC_HOST}"
log "  -> first visit shows the Create-admin form (no admin exists in the fresh DB yet)."
log "SECURITY GROUP REMINDER: this box needs inbound 80/tcp and 443/tcp open"
log "  (80 for Caddy's Let's Encrypt HTTP-01 challenge, 443 for the UI itself)."
log "  Port 8099 stays internal-only — Omnigent reaches the control plane over"
log "  localhost now that both run on this same box."
