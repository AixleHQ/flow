# frozen_string_literal: true

require "test_helper"

module Activities
  module AgentCredentials
    class FanOutActivityTest < ActiveSupport::TestCase
      CREDENTIALS_PATH = "/home/claude/.claude/.credentials.json"

      setup do
        @user = create(:user, :with_company)
        @company = @user.companies.first
        @project = create(:project, owner: @user, company: @company)
        @runtime = stub_container_runtime
        @credential = AgentCredential.from_artifacts(@user.id, @company.id, "claude_code", {
          "claudeAiOauth" => { "accessToken" => "at-2", "refreshToken" => "rt-2",
                               "expiresAt" => (8.hours.from_now.to_f * 1000).to_i }
        })
      end

      teardown do
        cleanup_runtime_overrides
      end

      def holder
        create(:terminal_session, session_type: "workflow_step", state: "ready", user: @user, project: @project,
                                  company: @company, agent_type: "claude_code", initial_prompt: "do the work",
                                  container_id: "ctr-#{SecureRandom.hex(3)}")
      end

      def fan_out(origin_session_id: nil)
        run_activity(FanOutActivity, Hashie::Mash.new(credential_id: @credential.id, origin_session_id: origin_session_id))
      end

      def delivered_refresh_token
        written = @runtime.read_file(nil, CREDENTIALS_PATH)
        written && JSON.parse(written).dig("claudeAiOauth", "refreshToken")
      end

      test "hands the stored grant to a live holder" do
        holder

        assert_equal 1, fan_out[:delivered]
        assert_equal "rt-2", delivered_refresh_token
      end

      test "skips the session the grant was written for" do
        origin = holder

        assert_equal 0, fan_out(origin_session_id: origin.id)[:delivered]
        assert_nil delivered_refresh_token
      end

      test "sends a paused holder back to its task" do
        session = holder
        session.merge_jsonb!(:metadata, "auth_paused_at" => 5.minutes.ago.iso8601)

        fan_out

        assert_includes @runtime.execs, [ "tmux", "send-keys", "-t", "agent", "-l", Agents::BaseAdapter::AUTH_RESUME_PROMPT ]
        refute Sessions::AuthPause.paused?(session.reload)
      end

      test "hands out nothing from a credential its owner has to sign in again for" do
        holder
        @credential.mark_refresh_error!("invalid_grant", permanent: true)

        assert_equal 0, fan_out[:delivered]
        assert_nil delivered_refresh_token
      end
    end
  end
end
