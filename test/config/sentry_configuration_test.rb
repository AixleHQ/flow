# frozen_string_literal: true

require "test_helper"

# The configuration every process shares (config/initializers/sentry.rb). Built
# on a fresh Sentry::Configuration so nothing depends on the test process having
# initialized Sentry at all.
class SentryConfigurationTest < ActiveSupport::TestCase
  def configured
    config = Sentry::Configuration.new
    SentryConfiguration.apply(config, dsn: nil)
    config
  end

  test "never ships PII, and keeps the default instrumentation" do
    config = configured

    assert_equal false, config.send_default_pii # rubocop:disable Minitest/RefuteFalse
    assert_includes config.enabled_patches, :logger
    assert_includes config.enabled_patches, :http
  end

  test "the OTLP ingest route is never traced" do
    sampler = configured.traces_sampler

    assert_equal false, sampler.call({ env: { "PATH_INFO" => "/api/v1/internal/usage_statistics" } }) # rubocop:disable Minitest/RefuteFalse
    assert_in_delta Settings.sentry.traces_sample_rate.to_f, sampler.call({ env: { "PATH_INFO" => "/company/projects" } })
  end

  test "request bodies are filtered, cookies and credential headers dropped" do
    request = Struct.new(:data, :cookies, :headers).new(
      { "config_item" => { "value" => "sk_live_x" }, "name" => "ok" },
      { "_aixle_session" => "abc" },
      { "Authorization" => "Bearer t", "X-Session-Key" => "k", "Accept" => "json" }
    )
    event = Struct.new(:request).new(request)

    SentryConfiguration.scrub_request(event)

    assert_equal "[FILTERED]", request.data.dig("config_item", "value")
    assert_equal "ok", request.data["name"]
    assert_empty request.cookies
    assert_equal({ "Accept" => "json" }, request.headers)
  end
end
