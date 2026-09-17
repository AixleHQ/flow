# frozen_string_literal: true

require "test_helper"

# docs/reference/configuration.md is the only description of the deployment
# surface, and it drifted badly while being the thing operators read: 35 of the
# variables in config/settings.yml had no row at all (OAUTH_SECRET_KEY among
# them — a secret production refuses to boot without), five rows stated the
# wrong default, and the copy the in-app docs portal serves had diverged from
# the file in docs/ it was hand-copied from.
class ConfigurationReferenceTest < ActiveSupport::TestCase
  REFERENCE = Rails.root.join("docs/reference/configuration.md")
  PORTAL_COPY = Rails.root.join("app/frontend/pages/Docs/data/pages/config-schema.md")
  SETTINGS_FILES = [ Rails.root.join("config/settings.yml"), *Rails.root.glob("config/settings/*.yml") ].freeze

  # Read by the settings files but not deployment configuration.
  NOT_CONFIGURATION = %w[HOME].freeze

  # Documented on purpose, read outside the settings files: the web servers'
  # own knobs (they boot before the settings gem), the boot switches, and the
  # development/test/seed inputs. Extend this list only for a variable that is
  # genuinely read somewhere — its point is to keep the reference from growing
  # rows for variables nothing consults.
  READ_OUTSIDE_SETTINGS = %w[
    ACTION_CABLE_URL AIXLE_TOOLS_RECONCILE_ON_BOOT CHROMIUM_PATH CI COVERAGE_MIN
    MCP_MAX_THREADS MCP_MIN_THREADS MCP_PIDFILE MCP_PORT PARALLEL_WORKERS PIDFILE PORT
    RAILS_ENV RAILS_LOG_LEVEL RAILS_LOG_TO_STDOUT RAILS_MIN_THREADS
    SEED_COMPANY_ADMIN_EMAIL SEED_COMPANY_EMAIL_DOMAIN SEED_COMPANY_NAME SEED_COMPANY_SLUG
    SKIP_COVERAGE SOLID_QUEUE_IN_PUMA WORKER_BOOT_CHECK_TIMEOUT
  ].freeze

  test "every variable the settings files read is documented" do
    undocumented = settings_variables - documented_variables - NOT_CONFIGURATION
    assert_empty undocumented,
      "add a row in docs/reference/configuration.md for: #{undocumented.to_a.sort.join(', ')}"
  end

  test "every documented variable is read somewhere" do
    unread = documented_variables - settings_variables - READ_OUTSIDE_SETTINGS
    assert_empty unread,
      "docs/reference/configuration.md documents variables nothing reads: #{unread.to_a.sort.join(', ')}"
  end

  test "the docs portal serves the same reference, not a hand-copy of it" do
    assert_equal REFERENCE.read, PORTAL_COPY.read,
      "run `bin/rails docs:sync_config_reference` to refresh the portal copy"
  end

  private

  def settings_variables
    SETTINGS_FILES.flat_map { |file| file.read.scan(/ENV(?:\.fetch)?[\[(]\s*['"]([A-Z0-9_]+)['"]/) }.flatten.to_set
  end

  # Only the first cell of a table row counts as documentation: prose (the
  # "Removed variables" list, for instance) names variables to say they are gone.
  def documented_variables
    REFERENCE.readlines.filter_map { |line| line[/\A\|\s*`([A-Z][A-Z0-9_]*)`/, 1] }.to_set
  end
end
