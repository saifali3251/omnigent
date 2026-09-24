#!/usr/bin/env bash
# provision-omnigent-gcp.sh — GCE counterpart of provision-omnigent-aws.sh.
#
# STATUS: UNVERIFIED. Written against documented gcloud/GCE metadata-server
# behavior; this environment has no GCP access (confirmed 2026-09-20). Do
# not treat this as tested just because provision-omnigent-aws.sh is.
#
# Assumes: Docker + the Holodeck control plane are already running on this
# VM (a separate clone/folder — this script assumes nothing about it beyond
# "port 8099 answers"). There is no GCE equivalent of setup-omnigent-poc-box.sh
# yet — see docs/09-gcp-integration-plan.md.
#
# Required env vars:
#   HOLODECK_TOKEN   must match the control plane's own HOLODECK_TOKEN
set -euo pipefail
: "${HOLODECK_TOKEN:?set HOLODECK_TOKEN - must match the control plane token}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="${OMNIGENT_DEPLOY_DIR:-$HERE/../omnigent}"

log() { printf '\033[34m[omnigent-gcp]\033[0m %s\n' "$*"; }

command -v docker >/dev/null 2>&1 || { echo "docker not found" >&2; exit 1; }
if [[ ! -f "$DEPLOY_DIR/.env" ]]; then
  if [[ -f "$DEPLOY_DIR/.env.example" ]]; then
    log "copying .env.example -> .env"
    cp "$DEPLOY_DIR/.env.example" "$DEPLOY_DIR/.env"
  else
    echo "no .env found at $DEPLOY_DIR/.env" >&2; exit 1
  fi
fi

# Ensure secrets are set in .env
sed -i.bak "s#^HOLODECK_TOKEN=.*#HOLODECK_TOKEN=${HOLODECK_TOKEN}#" "$DEPLOY_DIR/.env"
if grep -q '^OMNIGENT_ACCOUNTS_COOKIE_SECRET=$' "$DEPLOY_DIR/.env" || grep -q '^OMNIGENT_ACCOUNTS_COOKIE_SECRET=[[:space:]]*#' "$DEPLOY_DIR/.env"; then
  sed -i.bak "s#^OMNIGENT_ACCOUNTS_COOKIE_SECRET=.*#OMNIGENT_ACCOUNTS_COOKIE_SECRET=$(openssl rand -hex 32)#" "$DEPLOY_DIR/.env"
fi
if grep -q '^POSTGRES_PASSWORD=$' "$DEPLOY_DIR/.env"; then
  sed -i.bak "s#^POSTGRES_PASSWORD=.*#POSTGRES_PASSWORD=1234#" "$DEPLOY_DIR/.env"
fi

if ! ls "$HERE/../wheels"/*.whl >/dev/null 2>&1; then
  log "no wheel in ../wheels/ yet — running sync-wheel.sh"
  "$HERE/sync-wheel.sh"
fi

# GCE metadata server gives the external IP directly
PUBLIC_IP="$(curl -sf -H 'Metadata-Flavor: Google' 'http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip')"
PUBLIC_HOST="${PUBLIC_IP}.sslip.io"
log "public host for this VM: $PUBLIC_HOST"
sed -i.bak \
  -e "s#^OMNIGENT_ACCOUNTS_BASE_URL=.*#OMNIGENT_ACCOUNTS_BASE_URL=https://${PUBLIC_HOST}#" \
  -e "s#^OMNIGENT_SANDBOX_SERVER_URL=.*#OMNIGENT_SANDBOX_SERVER_URL=https://${PUBLIC_HOST}#" \
  -e "s#^OMNIGENT_PUBLIC_HOST=.*#OMNIGENT_PUBLIC_HOST=${PUBLIC_HOST}#" \
  "$DEPLOY_DIR/.env"

log "building + starting omnigent and caddy"
(cd "$DEPLOY_DIR" && docker compose build && docker compose --profile tls up -d)

log "done. Visit https://${PUBLIC_HOST}"
log "VPC FIREWALL REMINDER: needs an allow-rule for 80/tcp + 443/tcp ingress"
