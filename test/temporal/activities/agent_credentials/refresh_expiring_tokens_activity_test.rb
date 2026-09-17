# frozen_string_literal: true

require "test_helper"

module Activities
  module AgentCredentials
    # Runs the real activity through the SDK's serverless ActivityEnvironment
    # (docs/testing.md §2), against real credential rows and the canonical container-runtime
    # fake. The only stubbed boundary is the vendor's token endpoint (WebMock), so the
    # adapter's own refresh and the delivery back into the container are exercised rather
    # than described.
    class RefreshExpiringTokensActivityTest < ActiveSupport::TestCase
      CREDENTIALS_PATH = "/home/claude/.claude/.credentials.json"

      setup do
        @company = create(:company)
        @user = create(:user, company: @company)
        @runtime = stub_container_runtime
        Rails.logger.stubs(:info)
        Rails.logger.stubs(:warn)
      end

      teardown { cleanup_runtime_overrides }

      def claude_credential(expires_in: 5.minutes, refresh_token: "rt-old")
        AgentCredential.from_artifacts(@user.id, @company.id, "claude_code", {
          "claudeAiOauth" => { "accessToken" => "at-old", "refreshToken" => refresh_token,
                               "expiresAt" => (expires_in.from_now.to_f * 1000).to_i }
        })
      end

      def holder_session(container_id: "ctr-1", state: "ready")
        create(:terminal_session, user: @user, company_id: @company.id, agent_type: "claude_code",
                                  state: state, container_id: container_id)
      end

      def stub_token_endpoint(access_token: "at-new", refresh_token: "rt-new")
        stub_request(:post, Agents::ClaudeCodeAdapter::OAUTH_TOKEN_URL).to_return(
          status: 200,
          body: { access_token: access_token, refresh_token: refresh_token,
                  expires_in: 28_800, scope: "user:inference" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
      end

      # == The unheld path (unchanged behaviour) ==

      test "refreshes a credential no container holds" do
        credential = claude_credential
        stub_token_endpoint

        result = run_activity(RefreshExpiringTokensActivity)

        assert_equal 1, result[:refreshed]
        assert_equal "at-new", credential.reload.config_data.dig("claudeAiOauth", "accessToken")
      end

      test "returns zero counts when nothing is due" do
        claude_credential(expires_in: 6.hours)

        result = run_activity(RefreshExpiringTokensActivity)

        assert_equal 0, result[:refreshed]
        assert_equal 0, result[:errors]
      end

      test "condemns the credential when the vendor rejects the grant" do
        credential = claude_credential
        stub_request(:post, Agents::ClaudeCodeAdapter::OAUTH_TOKEN_URL)
          .to_return(status: 400, body: { error: "invalid_grant" }.to_json,
                     headers: { "Content-Type" => "application/json" })

        result = run_activity(RefreshExpiringTokensActivity)

        assert_equal 1, result[:errors]
        assert_equal "error", credential.reload.status
        assert_match(/invalid_grant/, credential.refresh_error)
      end

      # == The held path: refresh, then hand the result to the holder ==
      #
      # The production failure this replaces: a credential pinned by a session parked for
      # twenty hours was skipped every five minutes until its token expired unattempted.

      test "refreshes a credential a parked session holds and delivers it to the container" do
        credential = claude_credential
        session = holder_session
        @runtime.set_terminal_pane("waiting for input", last_output_at: 2.hours.ago)
        stub_token_endpoint

        result = run_activity(RefreshExpiringTokensActivity)

        assert_equal 1, result[:refreshed]
        assert_equal 1, result[:delivered]
        assert_equal 0, result[:skipped_busy]
        assert_equal "at-new", credential.reload.config_data.dig("claudeAiOauth", "accessToken")

        delivered = JSON.parse(@runtime.read_file(session.container_id, CREDENTIALS_PATH))
        assert_equal "at-new", delivered.dig("claudeAiOauth", "accessToken")
        assert_equal "rt-new", delivered.dig("claudeAiOauth", "refreshToken")
      end

      test "leaves a credential alone while its holder is mid-turn" do
        credential = claude_credential
        holder_session
        @runtime.set_terminal_pane("● Running tests…", last_output_at: 30.seconds.ago)

        result = run_activity(RefreshExpiringTokensActivity)

        assert_equal 0, result[:refreshed]
        assert_equal 1, result[:skipped_busy]
        assert_equal "at-old", credential.reload.config_data.dig("claudeAiOauth", "accessToken")
      end

      test "treats an unreadable container as busy rather than parked" do
        credential = claude_credential
        holder_session
        # No pane mtime at all: the reader cannot say when the session last spoke.
        @runtime.set_terminal_pane("", last_output_at: nil)

        result = run_activity(RefreshExpiringTokensActivity)

        assert_equal 1, result[:skipped_busy]
        assert_equal "at-old", credential.reload.config_data.dig("claudeAiOauth", "accessToken")
      end

      test "refreshes for a queued holder that has no container yet" do
        credential = claude_credential
        holder_session(container_id: nil, state: "queued")
        stub_token_endpoint

        result = run_activity(RefreshExpiringTokensActivity)

        assert_equal 1, result[:refreshed]
        assert_equal 0, result[:delivered], "a queued session reads the stored copy at launch"
        assert_equal "at-new", credential.reload.config_data.dig("claudeAiOauth", "accessToken")
      end

      test "a delivery failure does not undo the refresh" do
        credential = claude_credential
        holder_session
        @runtime.set_terminal_pane("waiting for input", last_output_at: 2.hours.ago)
        @runtime.stubs(:write_file).raises(StandardError.new("container gone"))
        stub_token_endpoint

        result = run_activity(RefreshExpiringTokensActivity)

        assert_equal 1, result[:refreshed]
        assert_equal 0, result[:delivered]
        assert_equal "at-new", credential.reload.config_data.dig("claudeAiOauth", "accessToken")
      end

      # == Batch behaviour ==

      test "one failing credential does not stop the batch" do
        other = create(:user, company: @company)
        bad = AgentCredential.from_artifacts(other.id, @company.id, "claude_code", {
          "claudeAiOauth" => { "accessToken" => "at-bad", "refreshToken" => "rt-bad",
                               "expiresAt" => (5.minutes.from_now.to_f * 1000).to_i }
        })
        good = claude_credential
        stub_request(:post, Agents::ClaudeCodeAdapter::OAUTH_TOKEN_URL)
          .with(body: hash_including("refresh_token" => "rt-bad"))
          .to_return(status: 500, body: "boom")
        stub_request(:post, Agents::ClaudeCodeAdapter::OAUTH_TOKEN_URL)
          .with(body: hash_including("refresh_token" => "rt-old"))
          .to_return(status: 200,
                     body: { access_token: "at-new", refresh_token: "rt-new", expires_in: 28_800 }.to_json,
                     headers: { "Content-Type" => "application/json" })

        result = run_activity(RefreshExpiringTokensActivity)

        assert_equal 1, result[:refreshed]
        assert_equal 1, result[:errors]
        assert_equal "at-new", good.reload.config_data.dig("claudeAiOauth", "accessToken")
        assert_equal "at-bad", bad.reload.config_data.dig("claudeAiOauth", "accessToken")
      end
    end
  end
end
