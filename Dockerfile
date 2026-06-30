FROM ruby:4.0.5-alpine

RUN apk update && \
    apk add --no-cache build-base postgresql-dev tzdata bash git vim curl yarn postgresql-client \
        less vips vips-dev vips-tools gcompat build-base yaml-dev file-dev openssh-client

# Coder CLI — used by Coder::SshRunner to exec commands on workspaces (N1 / DD-1).
# Only present in the Rails image; the workflow-step image deliberately does NOT
# receive the CLI or Coder env vars.
#
# Downloads the linux amd64 build from the GitHub release tarball. The tarball
# is small (~50MB) and ships a single `coder` binary plus license/readme files.
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
RUN bundle config set --local frozen true && bundle install

COPY package.json yarn.lock .yarnrc.yml  ./
COPY .yarn .yarn

RUN yarn set version 4.12.0
RUN yarn install

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

RUN RAILS_SECRET_KEY_BASE=secret \
    RAILS_ENV=production \
    AWS_EC2_METADATA_DISABLED=true \
    ASSET_HOST="${ASSET_HOST}" \
    VITE_RUBY_ASSET_HOST="${ASSET_HOST}" \
    rails assets:precompile

CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
