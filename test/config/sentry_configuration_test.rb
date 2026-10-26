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

  # Captures through a real hub and client, the way a deployed process sends, into the
  # SDK's own in-memory transport.
  def sent_events
    config = configured
    config.dsn = "http://public@sentry.test/1"
    config.environment = "production"
    config.background_worker_threads = 0
    config.transport.transport_class = Sentry::DummyTransport
    client = Sentry::Client.new(config)
    yield Sentry::Hub.new(client, Sentry::Scope.new)
    client.transport.events
  end

  test "a script that crashes `rails runner` is not reported, any other error is" do
    events = sent_events do |hub|
      # What sentry-rails' runner hook sends from its at_exit.
      hub.capture_exception(NoMethodError.new("undefined method 'project_id'"), tags: { source: "runner" })
      hub.capture_exception(NoMethodError.new("undefined method 'steps'"), tags: { agent_type: "claude" })
    end

    assert_equal [ { agent_type: "claude" } ], events.map(&:tags)
  end

  test "an error event that is sent is scrubbed first" do
    request = Struct.new(:data, :cookies, :headers).new(
      { "config_item" => { "value" => "sk_live_x" } }, { "_aixle_session" => "abc" }, { "Authorization" => "Bearer t" }
    )
    event = Struct.new(:tags, :request).new({}, request)

    assert_same event, configured.before_send.call(event, {})
    assert_equal "[FILTERED]", request.data.dig("config_item", "value")
    assert_empty request.cookies
    assert_empty request.headers
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

  test "the app tokens Forge sends with every Bitbucket invocation are dropped" do
    request = Struct.new(:data, :cookies, :headers).new(
      {}, {}, { "X-Forge-Oauth-System" => "app-token", "x-forge-oauth-user" => "user-token", "X-B3-Traceid" => "t" }
    )

    SentryConfiguration.scrub_request(Struct.new(:request).new(request))

    assert_equal({ "X-B3-Traceid" => "t" }, request.headers)
  end
end
