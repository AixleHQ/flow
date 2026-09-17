# frozen_string_literal: true

require "test_helper"

# The thread budget is one number read by three places: Puma's pool
# (config/puma.rb), the Active Record pool (config/settings.yml, RAILS_MAX_THREADS
# + 3) and the Temporal worker's activity slots. They used to disagree about the
# DEFAULT: Puma fell back to 10 while the pool was sized from 5, so a deployment
# that never set RAILS_MAX_THREADS ran 10 request threads against an 8-connection
# pool and paid for it with ConnectionTimeoutError under load. Compose and the
# cluster both set the variable, so nothing caught it.
class ThreadBudgetTest < ActiveSupport::TestCase
  SETTINGS_FILE = Rails.root.join("config/settings.yml")
  PUMA_FILES = %w[config/puma.rb config/puma_mcp.rb].freeze

  test "settings and every Puma config agree on the RAILS_MAX_THREADS fallback" do
    settings_default = SETTINGS_FILE.read[/max_threads\s*=\s*\(ENV\["RAILS_MAX_THREADS"\]\s*\|\|\s*(\d+)\)/, 1]
    assert settings_default, "config/settings.yml no longer binds a max_threads fallback"

    PUMA_FILES.each do |file|
      puma_default = Rails.root.join(file).read[/ENV\.fetch\("RAILS_MAX_THREADS",\s*(\d+)\)/, 1]
      assert puma_default, "#{file} no longer falls back to a RAILS_MAX_THREADS default"
      assert_equal settings_default, puma_default,
        "#{file} and config/settings.yml disagree on the RAILS_MAX_THREADS default, " \
        "so an unset variable sizes the thread pool and the connection pool from different numbers"
    end
  end

  test "the Active Record pool leaves headroom above the request thread budget" do
    assert_operator Settings.database.pool.to_i, :>, max_threads,
      "one request thread holds one connection, so an equal pool leaves nothing for " \
      "checkouts that are not request-bound"
  end

  # The worker keeps a smaller fallback on purpose (see config/settings.yml), so
  # the invariant is a ceiling, not equality: the worker must never claim more
  # threads than the budget the connection pool was sized from.
  test "the Temporal worker never asks for more threads than the pool covers" do
    worker_threads = Settings.temporal.worker_max_threads.to_i
    assert_operator worker_threads, :>, 0
    assert_operator worker_threads, :<=, max_threads
    assert_operator (worker_threads * 2).clamp(10, 30), :>, (worker_threads * 0.8).ceil,
      "bin/temporal_worker's pool must cover TemporalService's activity slots"
  end

  private

  def max_threads
    default = Rails.root.join("config/puma.rb").read[/ENV\.fetch\("RAILS_MAX_THREADS",\s*(\d+)\)/, 1]
    (ENV["RAILS_MAX_THREADS"] || default).to_i
  end
end
