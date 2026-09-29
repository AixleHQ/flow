# Two images from one file:
#   --target production   what a deployment runs: production gems, precompiled
#                          assets, runtime libraries only, and it runs as `app`.
#   (default)              the development image — compilers, Chromium, every gem
#                          group and node_modules — which Compose and CI build.
# The development stage is last so that a build naming no target keeps producing
# the image it always did.

FROM ruby:4.0.7-alpine AS base

# Runtime libraries of the gems' native extensions (pg → libpq, ruby-vips → vips,
# psych → yaml) and the tools the app itself runs.
RUN apk add --no-cache tzdata bash curl libpq postgresql-client vips yaml gcompat su-exec

# Coder CLI — used by Coder::SshRunner to exec commands on workspaces (N1 / DD-1).
# Only present in the Rails image; the workflow-step image deliberately does NOT
# receive the CLI or Coder env vars.
#
# Downloads the linux amd64 build from the GitHub release tarball (~175MB
# compressed, ~400MB installed) and ships a single `coder` binary plus
# license/readme files. The binary is this large because Coder only publishes
# "fat" builds — every release (all OSes/arches) embeds the web dashboard, so
# there's no official CLI-only artifact to switch to. A slim, dashboard-less
# binary exists as an internal build target in the coder repo (`make
# build/coder-slim_...`) but isn't published anywhere, including their own
# Docker images — using it here would mean building coder from source
# in-tree. Decided that's not worth it just to talk to workspaces over SSH;
# keeping the official fat binary.
ARG CODER_CLI_VERSION=v2.34.5
RUN set -eux; \
    curl -fsSL "https://github.com/coder/coder/releases/download/${CODER_CLI_VERSION}/coder_${CODER_CLI_VERSION#v}_linux_amd64.tar.gz" \
        -o /tmp/coder.tar.gz && \
    mkdir -p /tmp/coder-extract && \
    tar -xzf /tmp/coder.tar.gz -C /tmp/coder-extract && \
    find /tmp/coder-extract -type f -name coder -exec install -m 0755 {} /usr/local/bin/coder \; && \
    rm -rf /tmp/coder-extract /tmp/coder.tar.gz && \
    /usr/local/bin/coder version

# The app user (L-22) exists from here on, and everything under /app is written
# as that user rather than written as root and handed over at the end. A closing
# `chown -R app:app /app` reads cheap and is not: changing an owner rewrites every
# file underneath it into a fresh layer, so the image carried a second copy of
# most of node_modules. Measured on arm64: that one layer was 536 MB and the
# image 4.04 GB, against 3.50 GB with it gone. Every build wrote those 536 MB,
# every cache export stored them, and every CI job that materialises the image
# moves them.
RUN addgroup -S app && adduser -S app -G app
RUN mkdir /app && chown app:app /app
WORKDIR /app

FROM base AS build

RUN apk add --no-cache build-base postgresql-dev vips-dev yaml-dev git nodejs npm

# Corepack installs globally, so it has to happen while we are still root. Pinned:
# `corepack@latest` made each build install whatever npm served that day.
RUN npm install -g corepack@0.36.0 && corepack enable

USER app
ENV COREPACK_ENABLE_DOWNLOAD_PROMPT=0

# The ruby base image leaves GEM_HOME mode 1777 precisely so unprivileged users
# can install into it.
RUN gem install bundler -v 4.0.11

FROM build AS production-build

COPY --chown=app:app Gemfile Gemfile.lock .ruby-version ./
RUN bundle config set --local frozen true && \
    bundle config set --local without "development test" && \
    bundle install && \
    rm -rf "$GEM_HOME/cache"

# Yarn is provisioned via Corepack driven by the "packageManager" field in
# package.json — the Yarn release is NOT vendored into the repo.
COPY --chown=app:app package.json yarn.lock .yarnrc.yml ./
RUN corepack install && yarn install --immutable

COPY --chown=app:app . /app

# The placeholders only let `assets:precompile` boot in production mode
# (config/initializers/required_env.rb refuses to boot without them).
ARG ASSET_HOST
RUN RAILS_SECRET_KEY_BASE=secret \
    CREDENTIALS_SECRET_KEY=build_placeholder_32bytes_000000 \
    CONFIG_ITEMS_SECRET_KEY=build_placeholder_32bytes_000000 \
    INTEGRATIONS_SECRET_KEY=build_placeholder_32bytes_000000 \
    OAUTH_SECRET_KEY=build_placeholder_32bytes_000000 \
    AWS_S3_BUCKET=build-placeholder \
    RAILS_ENV=production \
    AWS_EC2_METADATA_DISABLED=true \
    ASSET_HOST="${ASSET_HOST}" \
    VITE_RUBY_ASSET_HOST="${ASSET_HOST}" \
    bin/rails assets:precompile && \
    rm -rf node_modules tmp/cache

FROM base AS production

COPY --from=production-build /usr/local/bundle /usr/local/bundle
COPY --from=production-build --chown=app:app /app /app

ENV PATH=/app/bin:$PATH

ARG APP_VERSION
ENV APP_VERSION=${APP_VERSION}
ARG ASSET_HOST
ENV ASSET_HOST=${ASSET_HOST}

# Runs as `app` even when a Kubernetes `command:` replaces the entrypoint — the
# way the worker, jobs and MCP workloads start — so none of them runs as root.
USER app

ENTRYPOINT ["bin/run-as-app"]
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]

FROM build AS development

USER root
RUN apk add --no-cache less vim vips-tools openssh-client chromium ttf-freefont font-noto nss freetype harfbuzz
USER app

COPY --chown=app:app Gemfile Gemfile.lock .ruby-version ./
RUN bundle config set --local frozen true && \
    bundle install && \
    rm -rf "$GEM_HOME/cache"

COPY --chown=app:app package.json yarn.lock .yarnrc.yml ./
RUN corepack install
RUN yarn install --immutable

COPY --chown=app:app . /app

ENV PATH=/app/bin:/app/node_modules/.bin:$PATH

ARG APP_VERSION
ENV APP_VERSION=${APP_VERSION}

ARG ASSET_HOST
ENV ASSET_HOST=${ASSET_HOST}
ENV VITE_RUBY_ASSET_HOST=${ASSET_HOST}

RUN RAILS_SECRET_KEY_BASE=secret \
    CREDENTIALS_SECRET_KEY=build_placeholder_32bytes_000000 \
    CONFIG_ITEMS_SECRET_KEY=build_placeholder_32bytes_000000 \
    INTEGRATIONS_SECRET_KEY=build_placeholder_32bytes_000000 \
    OAUTH_SECRET_KEY=build_placeholder_32bytes_000000 \
    AWS_S3_BUCKET=build-placeholder \
    RAILS_ENV=production \
    AWS_EC2_METADATA_DISABLED=true \
    ASSET_HOST="${ASSET_HOST}" \
    VITE_RUBY_ASSET_HOST="${ASSET_HOST}" \
    rails assets:precompile

# Back to root for the entrypoint: bin/run-as-app fixes ownership on the
# bundle_cache and app_home volumes, which are root-owned on first mount, before
# dropping to `app` with su-exec.
USER root

ENTRYPOINT ["bin/run-as-app"]
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
