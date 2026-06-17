FROM ruby:3.4.2-alpine

RUN apk update && \
    apk add --no-cache build-base postgresql-dev tzdata bash git vim curl yarn postgresql-client \
        less vips vips-dev vips-tools gcompat build-base yaml-dev file-dev

RUN mkdir /app
WORKDIR /app

COPY Gemfile Gemfile.lock ./

RUN gem install bundler -v 2.6.5
RUN bundle install

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
