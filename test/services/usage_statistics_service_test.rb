# frozen_string_literal: true

require "test_helper"

class UsageStatisticsServiceTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @session = create(:terminal_session, :running, user: @user, project: @project)
  end

  test "process persists usage and returns ok for a valid OTLP payload" do
    payload = otlp_payload(
      otlp_resource_metric(
        token: @session.route_token,
        tokens: { input: 120, output: 30, cacheRead: 10, cacheCreation: 5 },
        cost_usd: 0.5,
        model: "claude-sonnet-4-6"
      )
    )

    result = nil
    assert_difference("UsageStatistic.count", 1) do
      result = UsageStatisticsService.process(payload.to_json)
    end

    assert_equal :ok, result.status
    assert_nil result.error

    stat = @session.reload.usage_statistic
    assert stat.present?, "expected a usage_statistic to be persisted for the session"
    assert_equal 120, stat.input_tokens
    assert_equal 30, stat.output_tokens
    assert_equal 10, stat.cache_read_tokens
    assert_equal 5, stat.cache_write_tokens
    assert_equal 50, stat.cost_cents
    assert_equal "otlp", stat.source
    assert_equal 1, stat.events_count
    assert_equal [ "claude-sonnet-4-6" ], stat.models
    assert_equal 165, stat.total_tokens
  end

  test "process persists a usage_statistic for every referenced session" do
    other_session = create(:terminal_session, :running, user: @user, project: @project)

    payload = otlp_payload(
      otlp_resource_metric(token: @session.route_token, tokens: { input: 100 }, cost_usd: 0.1),
      otlp_resource_metric(token: other_session.route_token, tokens: { output: 200 }, cost_usd: 0.2)
    )

    result = nil
    assert_difference("UsageStatistic.count", 2) do
      result = UsageStatisticsService.process(payload.to_json)
    end

    assert_equal :ok, result.status
    assert_equal 100, @session.reload.usage_statistic.input_tokens
    assert_equal 200, other_session.reload.usage_statistic.output_tokens
  end

  test "process returns accepted without persisting when payload carries no session token" do
    result = nil
    assert_no_difference("UsageStatistic.count") do
      result = UsageStatisticsService.process('{"resourceMetrics":[]}')
    end

    assert_equal :accepted, result.status
    assert_nil result.error
  end

  test "process returns accepted without persisting when the session has no usage to record" do
    payload = otlp_payload(
      otlp_resource_metric(token: @session.route_token, tokens: { input: 0 }, cost_usd: 0.0)
    )

    result = nil
    assert_no_difference("UsageStatistic.count") do
      result = UsageStatisticsService.process(payload.to_json)
    end

    assert_equal :accepted, result.status
    assert_nil @session.reload.usage_statistic
  end

  # == Session keys ==
  #
  # The route token is in every terminal URL; only the key proves the batch came
  # from the container the session launched.

  test "a keyed session accepts a batch that carries its key" do
    keyed!(@session)
    payload = otlp_payload(otlp_resource_metric(token: @session.route_token, tokens: { input: 7 }, cost_usd: 0.01,
                                                key: UsageStatistics::SessionKey.generate(@session.route_token)))

    result = UsageStatisticsService.process(payload.to_json)

    assert_equal :ok, result.status
    assert_equal 7, @session.reload.usage_statistic.input_tokens
  end

  test "a keyed session refuses a batch that names it without the key, or with a wrong one" do
    keyed!(@session)

    [ nil, "0" * 64, UsageStatistics::SessionKey.generate("someone-else") ].each do |key|
      payload = otlp_payload(otlp_resource_metric(token: @session.route_token, tokens: { input: 999 }, cost_usd: 50.0,
                                                  key: key))

      result = UsageStatisticsService.process(payload.to_json)

      assert_equal :unauthorized, result.status
    end
    assert_nil @session.reload.usage_statistic
  end

  test "a batch keyed for one session cannot write into another" do
    victim = create(:terminal_session, :running, user: @user, project: @project)
    keyed!(@session)
    keyed!(victim)
    payload = otlp_payload(
      otlp_resource_metric(token: @session.route_token, tokens: { input: 5 }, cost_usd: 0.01,
                           key: UsageStatistics::SessionKey.generate(@session.route_token)),
      otlp_resource_metric(token: victim.route_token, tokens: { input: 999 }, cost_usd: 50.0)
    )

    result = UsageStatisticsService.process(payload.to_json)

    assert_equal :ok, result.status
    assert_equal 5, @session.reload.usage_statistic.input_tokens
    assert_nil victim.reload.usage_statistic
  end

  # Containers launched before keys existed keep reporting until they end.
  test "a session launched before keys existed is still accepted by token alone" do
    payload = otlp_payload(otlp_resource_metric(token: @session.route_token, tokens: { input: 3 }, cost_usd: 0.01))

    result = UsageStatisticsService.process(payload.to_json)

    assert_equal :ok, result.status
    assert_equal 3, @session.reload.usage_statistic.input_tokens
  end

  private

  def keyed!(session)
    session.update_column(:metadata, session.metadata.merge(UsageStatistics::SessionKey::LAUNCH_MARKER => 1))
  end

  # Build one OTLP resourceMetrics entry carrying the terminal_session_token on
  # the resource, a claude_code.token.usage sum (one data point per token type),
  # and an optional claude_code.cost.usage sum.
  def otlp_resource_metric(token:, tokens: {}, cost_usd: nil, model: "claude-sonnet-4-6", key: nil)
    data_points = tokens.map do |type, value|
      {
        "attributes" => [
          { "key" => "type", "value" => { "stringValue" => type.to_s } },
          { "key" => "model", "value" => { "stringValue" => model } }
        ],
        "asInt" => value.to_s
      }
    end

    metrics = []
    metrics << { "name" => "claude_code.token.usage", "sum" => { "dataPoints" => data_points } } if data_points.any?
    unless cost_usd.nil?
      metrics << {
        "name" => "claude_code.cost.usage",
        "sum" => { "dataPoints" => [ { "attributes" => [], "asDouble" => cost_usd } ] }
      }
    end

    attributes = [ { "key" => "terminal_session_token", "value" => { "stringValue" => token } } ]
    attributes << { "key" => "terminal_session_key", "value" => { "stringValue" => key } } if key

    { "resource" => { "attributes" => attributes }, "scopeMetrics" => [ { "metrics" => metrics } ] }
  end

  def otlp_payload(*resource_metrics)
    { "resourceMetrics" => resource_metrics }
  end
end
