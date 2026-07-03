source "https://rubygems.org"

ruby file: ".ruby-version"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.3"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
gem "responders"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use Tailwind CSS [https://github.com/rails/tailwindcss-rails]
# gem "tailwindcss-rails"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
gem "bcrypt", "~> 3.1.7"

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
gem "audited"
gem "config"
gem "enumerize"
gem "gitlab"
gem "haml-rails"
gem "hashie"
gem "kramdown"
gem "kramdown-parser-gfm"
gem "jwt"
gem "octokit"
gem "ts_routes"
gem "oj"
gem "pundit"
gem "pagy"
gem "rack-cors"
gem "ransack"
gem "rolify"
gem "ruby-filemagic", github: "stoivo/ruby-filemagic"
gem "virtus"

gem "sentry-ruby"
gem "sentry-rails"

gem "rails-i18n"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
# gem "tzinfo-data", platforms: %i[ windows jruby ]

gem "redis"

# Temporal workflow orchestration (official SDK)
gem "temporalio"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false
gem "csv" # Required for CSV parsing

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
# gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false
gem "vite_rails", "~> 3.0"
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

group :development, :test do
  # Testing tools
  gem "factory_bot_rails"
  gem "faker"

  # Debugging tools
  gem "debug"
  gem "dotenv-rails", require: false
  gem "bullet"
  gem "byebug"
  gem "pry-byebug"
  gem "pry-rails"

  gem "letter_opener"
  gem "letter_opener_web"
end

group :development do
  gem "foreman"
  gem "spring"

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
  gem "minitest-rails"
  gem "mocha"

  # Coverage and mocking
  gem "simplecov", require: false
  gem "webmock"

  # System testing
  gem "capybara", ">= 3"
end

gem "shrine", "~> 3.8"
gem "aws-sdk-s3", "~> 1.226"
gem "image_processing", "~> 1.14"

gem "faraday-retry", "~> 2.3"

gem "lograge", "~> 0.14.0"
gem "minitar"

gem "rotp", "~> 6.3"

# Docker API for container management
gem "docker-api", "~> 2.3"

# Kubernetes API client for container runtime
gem "kubeclient", "~> 4.13"
gem "websocket-client-simple", "~> 0.3"

# Temporal (Ruby worker/client)
# Note: temporal-ruby is early; validate in dev.
# gem "temporal-ruby", "~> 0.1"

gem "stackprof", "~> 0.2.28"
