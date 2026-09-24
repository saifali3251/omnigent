# Build context is THIS directory's parent (omnigent-deploy/), so run:
#   docker build -f omnigent/Dockerfile -t omnigent:local .
# from omnigent-deploy/ — or just `docker compose build` (docker-compose.yml
# already points at the right context).
#
# Deliberately knows nothing about Holodeck specifically. It installs
# whatever sandbox-provider wheel(s) sit in ../wheels/ at build time — today
# that's Holodeck's, via scripts/sync-wheel.sh. A future harness swap means
# dropping a different wheel into that same folder; this file doesn't change.
#
# Pinned to v0.8.2, NOT :latest. sitecustomize.py monkeypatches private,
# unversioned internals of omnigent.server.managed_hosts (ManagedSandboxConfig,
# parse_sandbox_config) — confirmed 2026-09-20 the hard way: :latest resolved
# to 0.14.0, whose ManagedSandboxConfig shape changed (gained a `.default`
# sub-object) and crashed server boot. Everything the sandbox-provider wheel
# was built and verified against — DEPLOY-MANAGED.md, the golden-build
# scripts' `omnigent==0.8.2` pins, a live server_version check in
# omnigent-runner-binding-bug-report.md — is 0.8.2. Confirmed v0.8.2 is a
# real published tag via the GHCR tags API before pinning to it (not a
# guess). Bumping this requires re-verifying sitecustomize.py's patches
# against whatever new version you pin to — don't bump it casually.
FROM ghcr.io/omnigent-ai/omnigent-server-kubernetes:v0.8.2

USER root

# Glob the install — never pin an exact wheel filename (a version bump then
# silently keeps installing the old one until someone remembers to edit
# this file — see scripts/sync-wheel.sh's own header for why it always
# clears old wheels before copying in a new one).
COPY wheels/*.whl /tmp/wheels/
RUN pip install --no-deps --target /opt/holodeck /tmp/wheels/*.whl \
    # psycopg2-binary: whatever sandbox-provider plugin is installed above
    # may need a Postgres driver (Holodeck's does, for its ticket-lookup
    # patch) and the wheel is installed --no-deps by design. Harmless to
    # install even if a future provider doesn't need it.
    && pip install --target /opt/holodeck psycopg2-binary \
    && rm -rf /tmp/wheels

# /opt/holodeck is an arbitrary path inside THIS image — it has no
# relationship to anything on the host VM (a sibling Holodeck control-plane
# process on the same box has its own, unrelated /opt/holo/holodeck
# directory). Kept as /opt/holodeck only because that's what the
# already-verified EKS deployment used (omnigent-deployment-file.txt) —
# change it freely if a future provider wants something else, as long as
# PYTHONPATH below matches.
ENV PYTHONPATH=/opt/holodeck

RUN groupadd -r omnigent && useradd -r -g omnigent -u 1000 omnigent \
    && mkdir -p /data/artifacts \
    && chown -R omnigent:omnigent /data/artifacts /app /opt/holodeck

USER omnigent
