#!/usr/bin/env bash
# pull-env.sh — pulls the Omnigent env bundle from a cloud secret store and
# writes omnigent/.env. CLOUD selects the backend so the same script (and
# the same secret *shape*, matching omnigent/.env.example) works on AWS now
# and GCP later without touching anything else in this folder.
#
# The secret itself (in either backend) must be a flat JSON object whose
# keys are exactly the variable names in ../omnigent/.env.example.
#
# Usage:
#   CLOUD=aws   SECRET_NAME=holodeck/omnigent-poc/credentials ./pull-env.sh
#   CLOUD=gcp   SECRET_NAME=holodeck-omnigent-poc-credentials ./pull-env.sh
#   CLOUD=local ./pull-env.sh   # copies .env.example — fill in by hand;
#                                 # use this for first bring-up or a laptop
#                                 # test, before any secret exists
#
# CLOUD=gcp is UNVERIFIED — written against gcloud's documented behavior,
# never run against a real project (no GCP access in this environment as
# of 2026-09-20). Do not treat it as tested just because CLOUD=aws is.
set -euo pipefail
CLOUD="${CLOUD:-local}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/../omnigent/.env"

log() { printf '\033[34m[pull-env]\033[0m %s\n' "$*"; }

case "$CLOUD" in
  aws)
    : "${SECRET_NAME:?set SECRET_NAME to the Secrets Manager secret id}"
    command -v aws >/dev/null 2>&1 || { echo "aws CLI not found" >&2; exit 1; }
    log "reading $SECRET_NAME from AWS Secrets Manager"
    aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" \
      --query SecretString --output text \
      | jq -r 'to_entries[] | "\(.key)=\(.value)"' > "$OUT"
    ;;
  gcp)
    log "WARNING: CLOUD=gcp is unverified — see the header of this script" >&2
    : "${SECRET_NAME:?set SECRET_NAME to the Secret Manager secret id}"
    command -v gcloud >/dev/null 2>&1 || { echo "gcloud CLI not found" >&2; exit 1; }
    log "reading $SECRET_NAME from GCP Secret Manager"
    gcloud secrets versions access latest --secret="$SECRET_NAME" \
      | jq -r 'to_entries[] | "\(.key)=\(.value)"' > "$OUT"
    ;;
  local)
    cp "$HERE/../omnigent/.env.example" "$OUT"
    log "wrote $OUT from .env.example — fill in the blanks by hand before first bring-up"
    ;;
  *)
    echo "CLOUD must be aws, gcp, or local (got: $CLOUD)" >&2
    exit 1
    ;;
esac
log "wrote $OUT"
