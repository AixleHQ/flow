# frozen_string_literal: true

require "test_helper"

module Insights
  class BackfillTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    setup do
      company = create(:company)
      @user = create(:user, company: company)
      @project = create(:project, company: company, owner: @user)
      connect_to_insights!(@project, share_prompts: false)
    end

    test "queues the sessions that ended in the last 30 days, for the cron to send" do
      recent = finished_session(3.days.ago)
      old = finished_session(40.days.ago)
      running = create(:terminal_session, :running, user: @user, project: @project, agent_type: "claude_code")

      queued = nil
      assert_no_enqueued_jobs(only: ExportSessionJob) { queued = Backfill.call(@project) }

      assert_equal 1, queued
      assert_equal [ recent.id ], InsightsSessionExport.pluck(:terminal_session_id)
      assert LlmCall.exists?(terminal_session: recent), "the session's calls were materialized first"
      assert_not LlmCall.exists?(terminal_session: old)
      assert_not InsightsSessionExport.exists?(terminal_session: running)
    end

    private

    # A session from before llm_calls: usage events only, nothing materialized yet.
    def finished_session(at)
      session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code", state: "finished",
                                          started_at: at - 10.minutes, finished_at: at)
      session.create_usage_statistic!(
        input_tokens: 0, output_tokens: 0, cache_write_tokens: 0, cache_read_tokens: 0, cost_cents: 0, source: "otlp",
        events_count: 1, events_data: [ { "model" => "claude-sonnet-4-5", "timestamp" => (at.to_f * 1000).to_i.to_s,
                                          "tokenUsage" => { "inputTokens" => 1, "totalCents" => 0.1 }, "source" => "otlp" } ]
      )
      session
    end
  end
end
