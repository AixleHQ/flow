# syntax=docker/dockerfile:1
#
# The published runner image, ghcr.io/aixlehq/aixle-runner:X.Y.Z
# (docs/design/agent-runtimes/DESIGN.md §14.2), built by the `runner-v*` lane,
# .github/workflows/runner-release.yml. It holds exactly the released binary of
# its platform: the lane builds the binaries once, attaches them to the GitHub
# Release with checksums.txt, and copies the same files in here, so the image and
# the release asset are one binary.
#
# Built with the context ./runner, after the lane has put
# dist/aixle-runner-linux-amd64 and dist/aixle-runner-linux-arm64 there:
#
#   docker buildx build --platform linux/amd64,linux/arm64 -f docker/runner/Dockerfile runner
#
# The dev `local` adapter's image, which builds from source, is docker/runner/local.

# Nothing runs at build time, so both platforms build without emulation.
FROM alpine:3.22
ARG TARGETARCH
COPY --chmod=0755 dist/aixle-runner-linux-${TARGETARCH} /usr/local/bin/aixle-runner
# Not root by default. Whoever runs the image decides what it may reach: the
# Kubernetes API for the controller (task 19) or, for a host runner, the Docker
# socket, which `docker run --user 0:0` reaches (see AIXLE_RUNNER_DIR below).
USER 10001:10001
# In a container the image tag is the version: the runner does not update itself
# (DESIGN.md §14.4). Its binary is root-owned, and a container recreated from the
# image would bring the old binary back anyway.
ENV AIXLE_RUNNER_NO_SELF_UPDATE=1
# A host runner in a container (DESIGN.md §14.4). The proxy sidecar bind-mounts
# the runner's own binary and its relay socket, from the state directory, and the
# Docker daemon resolves those paths on the machine, not in this container
# (runner/protocol/PROTOCOL.md §5.8). So with AIXLE_RUNNER_DIR set, to a directory
# of the machine mounted at the same path, the binary runs from, and the state
# lives in, that directory: `configure`, `unregister` and `--mode host` all use
# $AIXLE_RUNNER_DIR/state. Without it the entrypoint is the binary, as it was.
COPY --chmod=0755 <<'EOF' /usr/local/bin/aixle-runner-entrypoint
#!/bin/sh
set -eu
dir="${AIXLE_RUNNER_DIR:-}"
if [ -z "$dir" ]; then
  exec aixle-runner "$@"
fi
mkdir -p "$dir/bin" "$dir/state"
chmod 700 "$dir/state"
cp /usr/local/bin/aixle-runner "$dir/bin/aixle-runner.new"
mv "$dir/bin/aixle-runner.new" "$dir/bin/aixle-runner"
exec "$dir/bin/aixle-runner" "$@" --state-dir "$dir/state"
EOF
ENTRYPOINT ["aixle-runner-entrypoint"]
CMD ["--mode", "host"]
