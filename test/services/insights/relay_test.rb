# frozen_string_literal: true

require "test_helper"

# Insights::Relay and Insights::OtlpEnvelope (docs/design/insights-otlp-relay.md §4–§5):
# what an exported session's agent sends reaches the outbox enriched and masked, and the
# outbox reaches Insights at least once.
class Insights::RelayTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @session = create(:terminal_session, :running, user: @user, project: @project, agent_type: "claude_code")
    @integration = connect_to_insights!(@project, insights_project_id: "ip-7")
    @insights = FakeInsightsClient.new
  end

  test "a proven session's logs are kept as the agent wrote them, with Flow's identity and the session key removed" do
    Insights::Relay.capture(logs_payload(@session, extra_resource: { "user.email" => "agent@forged.test" }), [ @session ])

    batch = InsightsOtlpBatch.sole
    assert_equal [ "logs", 1, @integration, @project ], [ batch.signal, batch.record_count, batch.integration, batch.project ]
    resource = batch.request.dig("resourceLogs", 0)
    attrs = attributes(resource.dig("resource", "attributes"))
    assert_equal @user.email, attrs["user.email"]
    assert_equal "ip-7", attrs["insights.project.id"]
    assert_equal @session.id.to_s, attrs["aixle_flow.session.id"]
    assert_equal "claude-code", attrs["service.name"]
    assert_not attrs.key?("terminal_session_token")
    assert_not attrs.key?(UsageStatistics::SessionKey::ATTRIBUTE)

    record = resource.dig("scopeLogs", 0, "logRecords", 0)
    record_attrs = attributes(record["attributes"])
    assert_equal "user_prompt", record_attrs["event.name"]
    assert_equal "deploy it", record_attrs["prompt"]
    assert_match(/\A\h{32}\z/, record_attrs["aixle_flow.record.id"])
  end

  test "the same record gets the same id, so a re-send can be told apart from a new one" do
    2.times { Insights::Relay.capture(logs_payload(@session), [ @session ]) }

    ids = InsightsOtlpBatch.order(:id).map do |batch|
      attributes(batch.request.dig("resourceLogs", 0, "scopeLogs", 0, "logRecords", 0, "attributes"))["aixle_flow.record.id"]
    end
    assert_equal 1, ids.uniq.size
  end

  test "the session's own secrets are masked wherever they appear" do
    secret = create(:config_item, :secret, scope: @project, name: "DEPLOY_TOKEN", value: "tok_live_9f8e7d6c5b4a")
    @session.config_items << secret

    Insights::Relay.capture(logs_payload(@session.reload, prompt: "use tok_live_9f8e7d6c5b4a to deploy"), [ @session ])

    assert_not_includes Zlib.gunzip(InsightsOtlpBatch.sole.payload), "tok_live_9f8e7d6c5b4a"
  end

  test "metrics whose data points carry the session key are claimed by that session" do
    payload = { "resourceMetrics" => [ { "resource" => { "attributes" => [] }, "scopeMetrics" => [ { "metrics" => [
      { "name" => "kiro.credits", "sum" => { "dataPoints" => [ { "asDouble" => 0.4, "attributes" => session_attributes(@session) } ] } }
    ] } ] } ] }

    Insights::Relay.capture(payload, [ @session ])

    batch = InsightsOtlpBatch.sole
    assert_equal [ "metrics", 1 ], [ batch.signal, batch.record_count ]
    point = batch.request.dig("resourceMetrics", 0, "scopeMetrics", 0, "metrics", 0, "sum", "dataPoints", 0)
    assert_empty point["attributes"]
  end

  test "nothing is kept for a project that is not exported, or for a resource that proves no session" do
    other = create(:terminal_session, :running, user: @user, project: create(:project, company: @company, owner: @user))
    unproven = logs_payload(@session)
    unproven["resourceLogs"][0]["resource"]["attributes"].reject! { |kv| kv["key"] == UsageStatistics::SessionKey::ATTRIBUTE }

    Insights::Relay.capture(logs_payload(other), [ other ])
    Insights::Relay.capture(unproven, [ @session ])

    assert_equal 0, InsightsOtlpBatch.count
  end

  test "a broken batch never fails the ingest" do
    assert_nil Insights::Relay.capture({ "resourceLogs" => "garbage" }, [ @session ])
  end

  test "due rows are merged per signal into one request and deleted once accepted" do
    3.times { Insights::Relay.capture(logs_payload(@session), [ @session ]) }

    outcome = Insights::Relay.drain(client: @insights)

    assert_equal({ "delivered" => 3, "claimed" => 3 }, outcome[@integration.id])
    assert_equal [ [ :export, { secret: @integration.credentials_data["secret"], signal: "logs" } ] ], @insights.calls
    assert_equal 3, @insights.exported.sole["resourceLogs"].size
    assert_equal 0, InsightsOtlpBatch.count
  end

  test "a rate limit holds the rows until Retry-After and stops the drain" do
    Insights::Relay.capture(logs_payload(@session), [ @session ])
    Insights::Relay.capture(metrics_payload(@session), [ @session ])
    @insights.export_results = [ Insights::Client::ExportResult.new(status: 429, retry_after: 120) ]
    now = Time.current

    Insights::Relay.drain(client: @insights, now: now)

    assert_equal 1, @insights.calls.size
    assert_in_delta now + 120.seconds, InsightsOtlpBatch.find_by(signal: "logs").next_attempt_at, 1.second
    assert_equal 2, InsightsOtlpBatch.where(state: "pending", claimed_until: nil).count
  end

  test "an unreachable Insights backs the rows off, and a week of failures gives up" do
    Insights::Relay.capture(logs_payload(@session), [ @session ])
    old = InsightsOtlpBatch.sole
    Insights::Relay.capture(logs_payload(@session, prompt: "later"), [ @session ])
    old.update_columns(created_at: 8.days.ago)
    @insights.export_results = [ Insights::Client::ExportResult.new(status: 503) ]

    Insights::Relay.drain(client: @insights)

    assert_equal "failed", old.reload.state
    fresh = InsightsOtlpBatch.where.not(id: old.id).sole
    assert_equal [ "pending", 1, "Insights answered 503" ], [ fresh.state, fresh.attempts, fresh.last_error ]
    assert_operator fresh.next_attempt_at, :>, Time.current
  end

  test "a refused secret marks the connection broken and keeps the rows for the new one" do
    Insights::Relay.capture(logs_payload(@session), [ @session ])
    @insights.export_results = [ Insights::Client::ExportResult.new(status: 401) ]

    Insights::Relay.drain(client: @insights)

    assert_equal "error", @integration.reload.status
    assert_equal [ "pending", nil ], InsightsOtlpBatch.sole.slice(:state, :claimed_until).values
  end

  test "records Insights refuses are not retried, and say why" do
    Insights::Relay.capture(logs_payload(@session), [ @session ])
    @insights.export_results = [ Insights::Client::ExportResult.new(status: 200, rejected: 1, message: "unknown event") ]

    Insights::Relay.drain(client: @insights)

    batch = InsightsOtlpBatch.sole
    assert_equal "failed", batch.state
    assert_match(/refused 1 of 1 logs records: unknown event/, batch.last_error)
  end

  test "a request too large for Insights is split in half" do
    2.times { Insights::Relay.capture(logs_payload(@session), [ @session ]) }
    @insights.export_results = [ Insights::Client::ExportResult.new(status: 413) ]

    Insights::Relay.drain(client: @insights)

    assert_equal [ 2, 1, 1 ], @insights.exported.map { |request| request["resourceLogs"].size }
    assert_equal 0, InsightsOtlpBatch.count
  end

  test "a failed row is swept a week after it failed" do
    Insights::Relay.capture(logs_payload(@session), [ @session ])
    InsightsOtlpBatch.update_all(state: "failed", updated_at: 8.days.ago)

    Insights::Relay.drain(client: @insights)

    assert_equal 0, InsightsOtlpBatch.count
  end

  private

  def session_attributes(session)
    [ { "key" => "terminal_session_token", "value" => { "stringValue" => session.route_token } },
      { "key" => UsageStatistics::SessionKey::ATTRIBUTE,
        "value" => { "stringValue" => UsageStatistics::SessionKey.generate(session.route_token) } } ]
  end

  def logs_payload(session, prompt: "deploy it", extra_resource: {})
    resource = [ { "key" => "service.name", "value" => { "stringValue" => "claude-code" } }, *session_attributes(session) ] +
               extra_resource.map { |key, value| { "key" => key, "value" => { "stringValue" => value } } }
    record = { "timeUnixNano" => "1763000000000000000",
               "attributes" => [ { "key" => "event.name", "value" => { "stringValue" => "user_prompt" } },
                                 { "key" => "prompt", "value" => { "stringValue" => prompt } } ] }
    { "resourceLogs" => [ { "resource" => { "attributes" => resource },
                            "scopeLogs" => [ { "scope" => { "name" => "com.anthropic.claude_code.events" },
                                               "logRecords" => [ record ] } ] } ] }
  end

  def metrics_payload(session)
    { "resourceMetrics" => [ { "resource" => { "attributes" => session_attributes(session) },
                               "scopeMetrics" => [ { "metrics" => [ { "name" => "claude_code.cost.usage",
                                                                      "sum" => { "dataPoints" => [ { "asDouble" => 0.1 } ] } } ] } ] } ] }
  end

  def attributes(list)
    Array(list).to_h { |kv| [ kv["key"], kv["value"].values.first ] }
  end
end
