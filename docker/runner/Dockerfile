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
# Not root. Whoever runs the image decides what it may reach: the Docker socket
# for a host runner, the Kubernetes API for the controller (task 19).
USER 10001:10001
# In a container the image tag is the version: the runner does not update itself
# (DESIGN.md §14.4). Its binary is root-owned, and a container recreated from the
# image would bring the old binary back anyway.
ENV AIXLE_RUNNER_NO_SELF_UPDATE=1
ENTRYPOINT ["aixle-runner"]
CMD ["--mode", "host"]
