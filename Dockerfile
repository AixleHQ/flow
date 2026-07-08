FROM ruby:4.0.5-alpine

RUN apk update && \
    apk add --no-cache build-base postgresql-dev tzdata bash git vim curl nodejs npm postgresql-client \
        less vips vips-dev vips-tools gcompat build-base yaml-dev file-dev openssh-client \
        chromium ttf-freefont font-noto nss freetype harfbuzz su-exec

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

RUN mkdir /app
WORKDIR /app

COPY Gemfile Gemfile.lock .ruby-version ./

RUN gem install bundler -v 4.0.11
RUN bundle config set --local frozen true && \
    bundle install && \
    rm -rf "$GEM_HOME/cache"

# Yarn is provisioned via Corepack driven by the "packageManager" field in
# package.json — the Yarn release is NOT vendored into the repo.
RUN npm install -g corepack@latest && corepack enable

COPY package.json yarn.lock .yarnrc.yml ./
COPY .yarn/releases/ .yarn/releases/

RUN corepack install
RUN yarn install --immutable

COPY . /app

ENV PATH=/app/bin:/app/node_modules/.bin:$PATH

ARG APP_VERSION
ENV APP_VERSION=${APP_VERSION}

ARG AUTHOR_NAME
ENV AUTHOR_NAME=${AUTHOR_NAME}

ARG AUTHOR_EMAIL
ENV AUTHOR_EMAIL=${AUTHOR_EMAIL}

ARG ASSET_HOST
ENV ASSET_HOST=${ASSET_HOST}
ENV VITE_RUBY_ASSET_HOST=${ASSET_HOST}

ARG VITE_SENTRY_FRONTEND_DSN
ENV VITE_SENTRY_FRONTEND_DSN=${VITE_SENTRY_FRONTEND_DSN}

RUN RAILS_SECRET_KEY_BASE=secret \
    CREDENTIALS_SECRET_KEY=build_placeholder_32bytes_000000 \
    CONFIG_ITEMS_SECRET_KEY=build_placeholder_32bytes_000000 \
    INTEGRATIONS_SECRET_KEY=build_placeholder_32bytes_000000 \
    RAILS_ENV=production \
    AWS_EC2_METADATA_DISABLED=true \
    ASSET_HOST="${ASSET_HOST}" \
    VITE_RUBY_ASSET_HOST="${ASSET_HOST}" \
    rails assets:precompile

RUN addgroup -S app && adduser -S app -G app && chown -R app:app /app

ENTRYPOINT ["bin/run-as-app"]
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
