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
# Kubernetes API for the controller, which the pod spec starts with its own
# command, or, for a machine runner, the Docker socket, which `docker run
# --user 0:0` reaches.
USER 10001:10001
# In a container the image tag is the version: the runner does not update itself
# (DESIGN.md §14.4). Its binary is root-owned, and a container recreated from the
# image would bring the old binary back anyway.
ENV AIXLE_RUNNER_NO_SELF_UPDATE=1
# The two things that differ in a container, set explicitly: nothing is guessed
# from the filesystem (docs/design/agent-runtimes/add-machine.md §3.1, §3.2).
# - In a container the runner inspects its own container, only to learn where its
#   state directory lives on the machine, so that the proxy sidecar can mount a
#   part of it: a volume's subpath, or a directory under a bind's source.
# - Nothing is kept by default (the state directory is an anonymous volume, which
#   `docker run --rm` removes), so a stopped runner unregisters its machine. The
#   commands that keep the registration turn it off.
ENV AIXLE_RUNNER_IN_CONTAINER=1
ENV AIXLE_RUNNER_UNREGISTER_ON_STOP=1
# The runner's credentials, its journal and its copy of its own binary. Docker
# makes an anonymous volume of it unless the command mounts a volume or a
# directory there. There is no shell entrypoint: the runner copies its own binary
# into <state-dir>/bin and registers itself on its first start, from
# AIXLE_RUNNER_URL, AIXLE_RUNNER_TOKEN and AIXLE_RUNNER_NAME.
VOLUME /var/lib/aixle-runner
ENTRYPOINT ["aixle-runner"]
CMD ["--mode", "machine", "--state-dir", "/var/lib/aixle-runner"]
