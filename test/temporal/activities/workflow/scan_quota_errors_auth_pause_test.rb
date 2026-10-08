# frozen_string_literal: true

require "test_helper"

module Activities
  module Workflow
    # The quota scan's one pane read per session also decides whether an agent is waiting
    # for its login (Sessions::AuthPause, covered in its own test). Here: that the scan asks.
    class ScanQuotaErrorsAuthPauseTest < ActiveSupport::TestCase
      setup do
        @user = create(:user, :with_company)
        @company = @user.companies.first
        @project = create(:project, owner: @user, company: @company)
        @runtime = stub_container_runtime
        login = ->(token) { { "claudeAiOauth" => { "accessToken" => "at-#{token}", "refreshToken" => "rt-#{token}",
                                                   "expiresAt" => (6.hours.from_now.to_f * 1000).to_i } } }
        AgentCredential.from_artifacts(@user.id, @company.id, "claude_code", login.call(0))
        @credential = AgentCredential.from_artifacts(@user.id, @company.id, "claude_code", login.call(1))
        @session = create(:terminal_session, session_type: "workflow_step", state: "ready", mode: "non_interactive",
                                             user: @user, project: @project, company: @company, agent_type: "claude_code",
                                             container_id: "ctr-1", started_at: 1.hour.ago, initial_prompt: "do the work")
      end

      teardown do
        cleanup_runtime_overrides
      end

      test "pauses a step whose agent was refused a login nobody can renew, instead of failing it" do
        @credential.mark_refresh_error!("invalid_grant", permanent: true)
        @runtime.set_terminal_pane("  ⎿  Login expired · Please run /login\n> \n", last_output_at: 5.minutes.ago)

        result = run_activity(ScanQuotaErrorsActivity)

        assert_equal 1, result[:auth_paused]
        assert_equal 0, result[:cleaned]
        assert Sessions::AuthPause.paused?(@session.reload)
        assert_equal "ready", @session.state
      end

      test "sends a step straight back to work when the stored login is a working one" do
        @runtime.set_terminal_pane("  ⎿  Login expired · Please run /login\n> \n", last_output_at: 5.minutes.ago)

        result = run_activity(ScanQuotaErrorsActivity)

        assert_equal 0, result[:auth_paused]
        refute Sessions::AuthPause.paused?(@session.reload)
        assert_includes @runtime.execs, [ "tmux", "send-keys", "-t", "agent", "-l", Agents::BaseAdapter::AUTH_RESUME_PROMPT ]
      end

      test "still fails a step that ran out of credit" do
        @runtime.set_terminal_pane("Credit balance too low · Add funds: https://platform.claude.com/settings/billing\n",
                                   last_output_at: 5.minutes.ago)

        result = run_activity(ScanQuotaErrorsActivity)

        assert_equal 1, result[:cleaned]
        refute Sessions::AuthPause.paused?(@session.reload)
      end
    end
  end
end
