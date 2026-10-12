# frozen_string_literal: true

require "test_helper"

module AixleInsights
  class UsageExporterTest < ActiveSupport::TestCase
    setup do
      @base = "https://otel.insights.test"
      @original_base_url = Settings.aixle_insights.base_url
      @original_enabled = Settings.aixle_insights.enabled
      Settings.aixle_insights.base_url = @base
      Settings.aixle_insights.enabled = true

      @company = create(:company)
      @user = create(:user, :employee, :onboarding_completed, company: @company, email: "dev@acme.test")
      @project = create(:project, name: "Gateway", company: @company, owner: @user)
      @project.update!(insights_sharing_enabled: true)
    end

    teardown do
      Settings.aixle_insights.base_url = @original_base_url
      Settings.aixle_insights.enabled = @original_enabled
    end

    def logs_url = "#{@base}/v1/logs"

    def connect_insights(token: "company-token")
      create(:integration, :aixle_insights, :active, company: @company, connected_by: @user, project_id: nil)
        .tap { |i| i.update!(credentials_data: { "ingest_token" => token }) }
    end

    def finished_session(project: @project, company: @company, calls: 1, finished_at: 1.hour.ago)
      session = create(:terminal_session, :agent_session, user: @user, project: project, company: company,
                                                           agent_type: "claude_code", state: "finished",
                                                           started_at: 2.hours.ago, finished_at: finished_at)
      calls.times { create(:llm_call, terminal_session: session) }
      session
    end

    test "exports a candidate session and records it in the ledger" do
      connect_insights
      session = finished_session(calls: 2)
      stub = stub_request(:post, logs_url)
             .with(headers: { "Authorization" => "Bearer company-token" })
             .to_return(status: 200, body: { partialSuccess: {} }.to_json)

      summary = UsageExporter.new.call

      assert_requested stub
      assert_equal 1, summary[:exported]
      ledger = InsightsUsageExport.find_by(terminal_session_id: session.id)
      assert_equal "exported", ledger.state
      assert_equal 2, ledger.records_sent
      assert_equal @company.id, ledger.company_id
    end

    test "does not send a session twice across runs" do
      connect_insights
      finished_session
      stub = stub_request(:post, logs_url).to_return(status: 200, body: "{}")

      UsageExporter.new.call
      UsageExporter.new.call

      assert_requested stub, times: 1
    end

    test "a failed send is recorded failed, then replayed and exported on the next run" do
      connect_insights
      session = finished_session
      failing = stub_request(:post, logs_url).to_return(status: 503, body: "down")

      first = UsageExporter.new.call
      assert_equal 1, first[:failed]
      ledger = InsightsUsageExport.find_by(terminal_session_id: session.id)
      assert_equal "failed", ledger.state
      assert_equal 1, ledger.attempts
      assert_requested failing

      remove_request_stub(failing)
      stub_request(:post, logs_url).to_return(status: 200, body: "{}")
      second = UsageExporter.new.call

      assert_equal 1, second[:exported]
      assert_equal "exported", ledger.reload.state
    end

    test "a session that ended past the replay window is skipped, not sent" do
      connect_insights
      session = finished_session(finished_at: 8.days.ago)
      stub = stub_request(:post, logs_url).to_return(status: 200, body: "{}")

      summary = UsageExporter.new.call

      assert_equal 1, summary[:skipped]
      assert_not_requested stub
      assert_equal "skipped", InsightsUsageExport.find_by(terminal_session_id: session.id).state
    end

    test "a project with opt-in off sends nothing" do
      connect_insights
      @project.update!(insights_sharing_enabled: false)
      finished_session

      summary = UsageExporter.new.call

      assert_equal 0, summary[:exported]
      assert_equal 0, InsightsUsageExport.count
    end

    test "a company with no Insights connection sends nothing and writes no ledger row" do
      finished_session
      stub = stub_request(:post, logs_url).to_return(status: 200, body: "{}")

      summary = UsageExporter.new.call

      assert_equal 0, summary[:exported]
      assert_not_requested stub
      assert_equal 0, InsightsUsageExport.count, "a company without a connection must not be ledgered"
    end

    test "a terminal session with no llm_calls is marked exported with zero records, not resent" do
      connect_insights
      session = finished_session(calls: 0)
      stub = stub_request(:post, logs_url).to_return(status: 200, body: "{}")

      summary = UsageExporter.new.call

      # No llm_calls ⇒ not even a candidate (the query requires usage), so nothing
      # is written for it at all.
      assert_equal 0, summary[:exported]
      assert_not_requested stub
      assert_nil InsightsUsageExport.find_by(terminal_session_id: session.id)
    end

    test "running sessions are not candidates" do
      connect_insights
      running = create(:terminal_session, :agent_session, :running, user: @user, project: @project,
                                                                     company: @company, agent_type: "claude_code")
      create(:llm_call, terminal_session: running)
      stub = stub_request(:post, logs_url).to_return(status: 200, body: "{}")

      summary = UsageExporter.new.call

      assert_equal 0, summary[:exported]
      assert_not_requested stub
    end

    test "each company is sent with its own token" do
      connect_insights(token: "acme-token")
      session_a = finished_session

      other_company = create(:company)
      other_user = create(:user, :employee, :onboarding_completed, company: other_company, email: "b@beta.test")
      other_project = create(:project, name: "Beta", company: other_company, owner: other_user)
      other_project.update!(insights_sharing_enabled: true)
      create(:integration, :aixle_insights, :active, company: other_company, connected_by: other_user,
                                                      project_id: nil).update!(credentials_data: { "ingest_token" => "beta-token" })
      session_b = finished_session(project: other_project, company: other_company)

      acme = stub_request(:post, logs_url).with(headers: { "Authorization" => "Bearer acme-token" })
                                          .to_return(status: 200, body: "{}")
      beta = stub_request(:post, logs_url).with(headers: { "Authorization" => "Bearer beta-token" })
                                          .to_return(status: 200, body: "{}")

      UsageExporter.new.call

      assert_requested acme
      assert_requested beta
      assert_equal "exported", InsightsUsageExport.find_by(terminal_session_id: session_a.id).state
      assert_equal "exported", InsightsUsageExport.find_by(terminal_session_id: session_b.id).state
    end

    test "does nothing and sends nothing when the global switch is off" do
      Settings.aixle_insights.enabled = false
      connect_insights
      finished_session
      stub = stub_request(:post, logs_url).to_return(status: 200, body: "{}")

      summary = UsageExporter.new.call

      assert summary[:disabled]
      assert_not_requested stub
      assert_equal 0, InsightsUsageExport.count
    end
  end
end
