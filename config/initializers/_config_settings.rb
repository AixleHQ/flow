# frozen_string_literal: true

# Re-reads config/settings.yml now that ENV is complete. The config gem loads
# Settings before config/application.rb runs (which already reads it), but
# `Dotenv.load` runs later, in config/environments/development.rb and test.rb.
# Without this reload, values from `.env` never reach Settings in development
# and test, so everything read at boot (OmniAuth, Sentry, required_env.rb, the
# Temporal worker) would miss them. The leading underscore makes this run
# before the other initializers.
Settings.reload!
