# frozen_string_literal: true

require "test_helper"

module AixleInsights
  class OtlpLogsBuilderTest < ActiveSupport::TestCase
    setup do
      @company = create(:company)
      @user = create(:user, :employee, :onboarding_completed, company: @company, email: "dev@acme.test")
      @project = create(:project, name: "Gateway", company: @company, owner: @user)
      @session = create(:terminal_session, :agent_session, user: @user, project: @project,
                                                            company: @company, agent_type: "codex")
    end

    def resource_attrs(payload)
      payload[:resourceLogs][0][:resource][:attributes].to_h { |a| [ a[:key], a[:value] ] }
    end

    def log_records(payload)
      payload[:resourceLogs][0][:scopeLogs][0][:logRecords]
    end

    def record_attrs(record)
      record[:attributes].to_h { |a| [ a[:key], a[:value] ] }
    end

    test "build returns nil when the session has no llm_calls" do
      assert_nil OtlpLogsBuilder.new(@session).build
    end

    test "resource attributes carry service.name, agent type, user email and project name" do
      create(:llm_call, terminal_session: @session)

      attrs = resource_attrs(OtlpLogsBuilder.new(@session).build)

      assert_equal({ stringValue: "claude-code" }, attrs["service.name"])
      assert_equal({ stringValue: "codex" }, attrs["aixle.agent_type"])
      assert_equal({ stringValue: "dev@acme.test" }, attrs["user_email"])
      assert_equal({ stringValue: "Gateway" }, attrs["project_name"])
    end

    test "a two-call session produces one api_request record per call, oldest first" do
      create(:llm_call, terminal_session: @session, model: "claude-sonnet-4-5",
                        input_tokens: 1000, output_tokens: 200, cache_read_tokens: 30,
                        cache_write_tokens: 5, total_cents_precise: "1.50000000",
                        occurred_at: 1.hour.ago)
      create(:llm_call, terminal_session: @session, model: "gpt-5", occurred_at: 2.hours.ago)

      records = log_records(OtlpLogsBuilder.new(@session).build)
      assert_equal 2, records.size

      first = record_attrs(records[0])
      assert_equal({ stringValue: "gpt-5" }, first["model"], "records are ordered by occurred_at")

      second = record_attrs(records[1])
      assert_equal({ stringValue: "api_request" }, second["event.name"])
      assert_equal({ stringValue: @session.id.to_s }, second["session.id"])
      assert_equal({ stringValue: "claude-sonnet-4-5" }, second["model"])
      assert_equal({ intValue: 1000 }, second["input_tokens"])
      assert_equal({ intValue: 200 }, second["output_tokens"])
      assert_equal({ intValue: 30 }, second["cache_read_tokens"])
      assert_equal({ intValue: 5 }, second["cache_creation_tokens"], "cache_write maps to cache_creation")
      assert_in_delta 0.015, second["cost_usd"][:doubleValue], 1e-9
    end

    test "timeUnixNano is the call's occurred_at in nanoseconds" do
      at = Time.utc(2026, 1, 2, 3, 4, 5)
      create(:llm_call, terminal_session: @session, occurred_at: at)

      record = log_records(OtlpLogsBuilder.new(@session).build).first

      assert_equal (at.to_r * 1_000_000_000).to_i.to_s, record[:timeUnixNano]
    end

    test "a session with no project omits project_name rather than failing" do
      session = create(:terminal_session, :agent_session, user: @user, project: nil, company: @company)
      create(:llm_call, terminal_session: session)

      attrs = resource_attrs(OtlpLogsBuilder.new(session).build)

      assert_not attrs.key?("project_name")
      assert_equal({ stringValue: "dev@acme.test" }, attrs["user_email"])
    end

    test "a session whose user was deleted omits user_email rather than failing" do
      create(:llm_call, terminal_session: @session)
      @session.update_column(:user_id, nil)

      attrs = resource_attrs(OtlpLogsBuilder.new(@session.reload).build)

      assert_not attrs.key?("user_email")
      assert_equal({ stringValue: "Gateway" }, attrs["project_name"])
    end
  end
end
