# frozen_string_literal: true

require "test_helper"

module Agents
  class CredentialFanOutJobTest < ActiveJob::TestCase
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

    def holder(session_type: "workflow_step", state: "ready")
      create(:terminal_session, session_type: session_type, state: state, user: @user, project: @project,
                                company: @company, agent_type: "claude_code", initial_prompt: "do the work",
                                container_id: "ctr-#{SecureRandom.hex(3)}")
    end

    def delivered_refresh_token
      written = @runtime.read_file(nil, CREDENTIALS_PATH)
      written && JSON.parse(written).dig("claudeAiOauth", "refreshToken")
    end

    test "hands the stored grant to a live holder" do
      holder

      CredentialFanOutJob.perform_now(@credential.id)

      assert_equal "rt-2", delivered_refresh_token
    end

    test "skips the session the grant was written for" do
      origin = holder

      CredentialFanOutJob.perform_now(@credential.id, origin.id)

      assert_nil delivered_refresh_token
    end

    test "sends a paused holder back to its task" do
      session = holder
      session.merge_jsonb!(:metadata, "auth_paused_at" => 5.minutes.ago.iso8601)

      CredentialFanOutJob.perform_now(@credential.id)

      assert_includes @runtime.execs, [ "tmux", "send-keys", "-t", "agent", "-l", BaseAdapter::AUTH_RESUME_PROMPT ]
      refute Sessions::AuthPause.paused?(session.reload)
    end

    test "hands out nothing from a credential its owner has to sign in again for" do
      holder
      @credential.mark_refresh_error!("invalid_grant", permanent: true)

      CredentialFanOutJob.perform_now(@credential.id)

      assert_nil delivered_refresh_token
    end
  end
end
