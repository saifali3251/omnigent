#!/usr/bin/env bash
# sync-wheel.sh — the ONE place in this folder that knows Holodeck exists.
# Everything else here (Dockerfile, docker-compose.yml) only ever looks at
# ../wheels/*.whl and has no idea what produced it. Swapping to a different
# harness later means writing a different sync script (or none, if the new
# harness hands you a wheel directly) — not touching the Dockerfile.
#
# What it does: clears ../wheels/, optionally rebuilds the provider wheel
# from source, then copies the current .whl into ../wheels/. Always clears
# first — DEPLOY-MANAGED.md documents a real incident where a stale wheel
# left alongside a new one got installed instead ("the older can win" when
# pip's glob sees two candidates).
#
# Usage:
#   ./sync-wheel.sh                # copy whatever's already built in dist/
#   ./sync-wheel.sh --build        # rebuild from source first (needs `pip
#                                   # install build` in your environment —
#                                   # the provider uses a standard
#                                   # pyproject.toml + hatchling backend)
#
# Env override (default assumes the sibling layout this repo currently
# has — code/holodeck/ and code/omnigent-deploy/ side by side):
#   PROVIDER_DIR=/path/to/omnigent-provider ./sync-wheel.sh
if [[ -z "${PROVIDER_DIR:-}" ]]; then
  if [[ -d "/opt/holo/holodeck/control-plane/omnigent-provider" ]]; then
    PROVIDER_DIR="/opt/holo/holodeck/control-plane/omnigent-provider"
  elif [[ -d "$HERE/../../meeseek/control-plane/omnigent-provider" ]]; then
    PROVIDER_DIR="$HERE/../../meeseek/control-plane/omnigent-provider"
  else
    PROVIDER_DIR="$HERE/../../holodeck/control-plane/omnigent-provider"
  fi
fi
WHEELS_DIR="$HERE/../wheels"

log() { printf '\033[34m[sync-wheel]\033[0m %s\n' "$*"; }

[[ -d "$PROVIDER_DIR" ]] || { echo "PROVIDER_DIR not found: $PROVIDER_DIR" >&2; exit 1; }

if [[ "${1:-}" == "--build" ]]; then
  log "rebuilding wheel from source in $PROVIDER_DIR"
  log "(bump the version in pyproject.toml first if this is a real change —"
  log " installing over the same version number risks pip treating it as a no-op)"
  ( cd "$PROVIDER_DIR" && python3 -m build --wheel )
fi

latest="$(ls -t "$PROVIDER_DIR"/dist/*.whl 2>/dev/null | head -1)"
[[ -n "$latest" ]] || { echo "no .whl found in $PROVIDER_DIR/dist — run with --build first" >&2; exit 1; }

log "clearing $WHEELS_DIR (avoids an old wheel lingering alongside the new one)"
rm -f "$WHEELS_DIR"/*.whl
cp "$latest" "$WHEELS_DIR/"
log "synced $(basename "$latest") into $WHEELS_DIR"
log "next: docker compose build (in ../omnigent/) to bake it into the image, then"
log "      docker compose up -d --force-recreate omnigent to actually run the new build"
