# frozen_string_literal: true

source "https://rubygems.org"

ruby file: ".ruby-version"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.3"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.6"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"

# Durable ActiveJob backend. Without it Rails falls back to the in-memory async
# adapter, where an enqueued mail is lost on restart — and the invitation mail is
# the only way a person gets into the product.
gem "solid_queue", "~> 1.7"
# Use Tailwind CSS [https://github.com/rails/tailwindcss-rails]
# gem "tailwindcss-rails"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
gem "bcrypt", "~> 3.1.22"

# Authentication
gem "omniauth"
gem "omniauth-google-oauth2"
gem "omniauth-rails_csrf_protection"

gem "aasm"

gem "administrate"
gem "administrate-field-shrine"
gem "administrate-field-jsonb"
# Asset pipeline for the Administrate admin UI. Administrate <1.0 pulled in
# sprockets-rails transitively; 1.0 dropped that and ships precompiled assets,
# so we now declare a pipeline directly (Propshaft serves the gem's prebuilt
# CSS/JS without a compile step). See administrate docs/migrating-to-v1.md.
gem "propshaft"
gem "config"
gem "enumerize"
gem "gitlab"
gem "haml-rails"
gem "hashie"
gem "jwt"
gem "octokit"
gem "ts_routes"
gem "pundit"
gem "pagy"
gem "rack-attack"
gem "rack-cors"
gem "ransack"

gem "sentry-ruby"
gem "sentry-rails"

gem "rails-i18n"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
# gem "tzinfo-data", platforms: %i[ windows jruby ]

# Action Cable's Redis adapter asks for redis >= 4, < 6 when it loads (until Rails
# 8.2 moves it onto redis-client), and only production loads it: the test env's
# cable adapter is `test`, so a redis 6 bump passed CI and would have failed at
# boot. test/config/action_cable_redis_test.rb loads the adapter to catch that.
gem "redis", ">= 4", "< 6"

# Temporal workflow orchestration (official SDK)
gem "temporalio"

# Held below json 3.0, whose `JSON.parse` takes its options as keywords only and
# rejects `create_additions`, an option json 3 removed. temporalio's payload
# converter passes them positionally (`JSON.parse(payload.data, @parse_options)`
# in converters/payload_converter/json_plain.rb), so under json 3 every payload
# decode raises ArgumentError and every workflow task fails — the worker retries
# them forever rather than erroring out, which reads as a hang, not a failure.
# Present in temporalio 1.7, 1.8 and 1.9 alike. The SDK's default options are
# `{ create_additions: true }`; TemporalService.data_converter already passes none,
# so the pin can go once the SDK switches to keywords.
gem "json", "< 3"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false
gem "csv" # Required for CSV parsing

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
# gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false
gem "vite_rails", "~> 3.11"
gem "oas_rails"

# Inertia.js - modern monolith (server-side routing + React components)
gem "inertia_rails"
gem "inertia_cable"

# Alba - fast serializer with Typelizer support
gem "alba"

# Typelizer - auto-generate TypeScript interfaces from Alba resources
gem "typelizer"

# gem "image_processing", "~> 1.2"

# JSON Schema 2020-12 meta-validation of tenant-authored tool schemas
# (Tool#custom_definition_hygiene). Also an mcp-gem dependency.
gem "json_schemer"

# MCP (Model Context Protocol) server — official Ruby SDK. A stateless
# MCP::Server is built per request from the authenticated TerminalSession
# (McpController + Tools::McpRequestHandler).
gem "mcp"

# SSE frame parser for the mcp gem's HTTP CLIENT. The gem leaves it out of its
# gemspec so server-only users don't carry it, and `require`s it lazily the
# first time a Streamable HTTP server answers `content-type: text/event-stream`
# — which most remote MCP servers do, GitHub's included. Absent from the bundle
# that require raises LoadError out of MCP::ToolListProbe and 500s connector
# installation, so it is a hard dependency for us, not an optional one.
gem "event_stream_parser", ">= 1.0"

group :development, :test do
  # Testing tools
  gem "factory_bot_rails"
  gem "faker"

  # Debugging tools
  gem "debug"
  gem "dotenv-rails", require: false
  gem "bullet"
  gem "pry-byebug"
  gem "pry-rails"

  gem "letter_opener"
  gem "letter_opener_web"
end

group :development do
  gem "foreman"

  # Rubocop and related gems
  gem "rubocop"
  gem "rubocop-factory_bot"
  gem "rubocop-minitest"
  gem "rubocop-performance"
  gem "rubocop-rails"
  gem "rubocop-rails-omakase"

  # Security tools
  gem "brakeman", require: false

  # Dependency license reports
  gem "license_finder", require: false
end

group :test do
  # Rails testing
  gem "minitest"
  gem "minitest-hooks"
  gem "minitest-power_assert"
  gem "mocha"
  # One-time-password secrets for test fixtures only.
  gem "rotp", "~> 6.3"

  # Coverage and mocking
  gem "simplecov", require: false
  gem "webmock"

  # System testing (Capybara + Cuprite headless-Chrome driver + SitePrism page objects)
  gem "capybara", ">= 3"
  gem "cuprite"
  gem "site_prism"
end

gem "shrine", "~> 3.10"
# Content types, for Shrine's determine_mime_type analyzer and the code that labels
# session logs and step outputs. Nothing else requires it: the app does not load
# Active Storage, which would.
gem "marcel", "~> 1.0"
gem "aws-sdk-s3", "~> 1.232"

# Bedrock runtime, for the cloud-connection health check: the only way to tell a user
# their permission set cannot actually invoke a model is to try. Claude Code hides
# Bedrock errors, so without this the failure surfaces as an agent that never answers.
# (STS, SSO and SSO-OIDC clients already ship inside aws-sdk-core.)
gem "aws-sdk-bedrockruntime", "~> 1.85"

# Bedrock control plane, for listing the inference profiles an account can actually invoke.
# That list is the only truthful model catalogue for a Bedrock connection — it includes the
# account's own application inference profiles, which is what enterprise deployments pin.
gem "aws-sdk-bedrock", "~> 1.94"
gem "image_processing", "~> 2.1"
gem "ruby-vips", "~> 2.3" # image_processing 2.0 no longer declares it; shrine.rb requires image_processing/vips

gem "faraday-retry", "~> 2.3"

gem "lograge", "~> 0.15.0"

# Reads ONE credential format, not an application database. Kiro CLI keeps its login in
# a SQLite file rather than a JSON document, so Agents::KiroCliAdapter has to open that
# file to lift the bearer token and profile ARN its API calls need. Every other runtime
# hands us JSON and needs nothing here.
gem "sqlite3", "~> 2.9"

# Docker API for container management
gem "docker-api", "~> 2.3"

# Kubernetes API client for container runtime
gem "kubeclient", "~> 4.13"
gem "websocket-client-simple", "~> 0.3"

# Temporal (Ruby worker/client)
# Note: temporal-ruby is early; validate in dev.
# gem "temporal-ruby", "~> 0.1"

gem "stackprof", "~> 0.2.28"
