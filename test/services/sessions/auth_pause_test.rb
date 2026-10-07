# frozen_string_literal: true

require "test_helper"

module Sessions
  class AuthPauseTest < ActiveSupport::TestCase
    BANNER_PANE = <<~PANE
      ● Running the test suite
        ⎿  Login expired · Please run /login

      ╭──────────────────────────────────────────╮
      │ >                                        │
      ╰──────────────────────────────────────────╯
    PANE

    setup do
      @user = create(:user, :with_company)
      @company = @user.companies.first
      @project = create(:project, owner: @user, company: @company)
      @run = create(:workflow_run, workflow: create(:workflow, scope: @project), project: @project, user: @user,
                                   state: "running", started_at: 1.hour.ago)
      @session = step_session
      @runtime = stub_container_runtime
      @runtime.set_terminal_pane(BANNER_PANE, last_output_at: 5.minutes.ago)
      # Another container spent the shared refresh token a moment ago: the stored grant is the
      # one that replaced it.
      AgentCredential.from_artifacts(@user.id, @company.id, "claude_code", login("at-0", "rt-0"))
      @credential = AgentCredential.from_artifacts(@user.id, @company.id, "claude_code", login("at-1", "rt-1"))
    end

    teardown do
      cleanup_runtime_overrides
    end

    def step_session
      session = create(:terminal_session, session_type: "workflow_step", state: "ready", mode: "non_interactive",
                                          user: @user, project: @project, company: @company, agent_type: "claude_code",
                                          container_id: "ctr-#{SecureRandom.hex(3)}", started_at: 1.hour.ago,
                                          initial_prompt: "do the work")
      create(:step_run, :running, workflow_run: @run, terminal_session: session)
      session
    end

    def login(access_token, refresh_token)
      { "claudeAiOauth" => { "accessToken" => access_token, "refreshToken" => refresh_token,
                             "expiresAt" => (6.hours.from_now.to_f * 1000).to_i } }
    end

    def observe(session = @session)
      AuthPause.new(session.reload, runtime: @runtime).observe(BANNER_PANE)
    end

    RESUME_PROMPT_TYPED = [ "tmux", "send-keys", "-t", "agent", "-l", Agents::BaseAdapter::AUTH_RESUME_PROMPT ].freeze

    def delivered_refresh_token
      written = @runtime.read_file(nil, "/home/claude/.claude/.credentials.json")
      written && JSON.parse(written).dig("claudeAiOauth", "refreshToken")
    end

    # The usual case: another container spent the shared refresh token first, and the grant
    # that replaced it is already stored. Handing it over is the whole repair.
    test "hands a refused agent the grant already stored and sends it back to its task" do
      assert_equal :resumed, observe

      assert_equal "rt-1", delivered_refresh_token
      assert_includes @runtime.execs, RESUME_PROMPT_TYPED
      refute AuthPause.paused?(@session.reload)
      assert_equal "running", @run.reload.state
      assert_equal "ready", @session.state, "the container and the agent's work are kept"
    end

    test "renews a stored grant that is not recent before handing it over" do
      travel 30.minutes
      stub_request(:post, Agents::ClaudeCodeAdapter::OAUTH_TOKEN_URL)
        .with(body: hash_including("refresh_token" => "rt-1"))
        .to_return(status: 200, body: { access_token: "at-2", refresh_token: "rt-2", expires_in: 28_800 }.to_json,
                   headers: { "Content-Type" => "application/json" })

      assert_equal :resumed, observe

      assert_equal "rt-2", @credential.reload.config_data.dig("claudeAiOauth", "refreshToken")
      assert_equal "rt-2", delivered_refresh_token
    end

    test "pauses the step and its run when the login cannot be renewed" do
      @credential.mark_refresh_error!("invalid_grant", permanent: true)

      assert_equal :paused, observe

      assert AuthPause.paused?(@session.reload)
      assert_match %r{Login expired · Please run /login}, @session.metadata["auth_pause_reason"]
      assert_equal "paused", @run.reload.state
      assert_nil delivered_refresh_token
      refute_includes @runtime.execs, RESUME_PROMPT_TYPED
    end

    test "leaves an agent that is still producing output alone" do
      @runtime.set_terminal_pane(BANNER_PANE, last_output_at: 10.seconds.ago)

      assert_nil observe
      refute AuthPause.paused?(@session.reload)
      assert_equal "running", @run.reload.state
    end

    test "does not pause again on a banner the agent was already sent past" do
      pane = "#{BANNER_PANE}\n> #{Agents::BaseAdapter::AUTH_RESUME_PROMPT}\n● Continuing with the test suite\n"

      assert_nil AuthPause.new(@session, runtime: @runtime).observe(pane)
    end

    test "never pauses a runtime that does not name its expired-login banner" do
      @session.update!(agent_type: "codex")

      assert_nil observe
    end

    test "decides nothing on a pane it could not read" do
      assert_nil AuthPause.new(@session, runtime: @runtime).observe("")
    end

    test "fails the step once nobody has signed in again within the limit" do
      @session.merge_jsonb!(:metadata, "auth_paused_at" => (AuthPause.limit + 1.minute).ago.iso8601,
                                       "auth_pause_reason" => "Login expired · Please run /login")

      assert_equal :failed, observe

      @session.reload
      assert_equal "failed", @session.state
      assert_match(/agent authentication failed — Login expired/, @session.error_message)
    end

    test "lets a paused step go once the banner has left its pane" do
      @session.merge_jsonb!(:metadata, "auth_paused_at" => 5.minutes.ago.iso8601)
      @run.pause!

      assert_equal :resumed, AuthPause.new(@session.reload, runtime: @runtime).observe("● tick-12\n● tick-13\n> \n")
      refute AuthPause.paused?(@session.reload)
      assert_equal "running", @run.reload.state
    end

    # Opening the session's terminal in a browser redraws the CLI and moves the pane log.
    test "a redrawn terminal still showing the banner stays paused" do
      @credential.mark_refresh_error!("invalid_grant", permanent: true)
      @session.merge_jsonb!(:metadata, "auth_paused_at" => 5.minutes.ago.iso8601)
      @runtime.set_terminal_pane(BANNER_PANE, last_output_at: 5.seconds.ago)

      assert_equal :paused, observe
      assert AuthPause.paused?(@session.reload)
    end

    test "types the resume prompt into a paused agent and lets its run go on" do
      @session.merge_jsonb!(:metadata, "auth_paused_at" => 5.minutes.ago.iso8601)
      @run.pause!

      assert AuthPause.new(@session, runtime: @runtime).resume!

      assert_includes @runtime.execs, RESUME_PROMPT_TYPED
      assert_includes @runtime.execs, [ "tmux", "send-keys", "-t", "agent", "Enter" ]
      refute AuthPause.paused?(@session.reload)
      assert_equal "running", @run.reload.state
    end

    test "keeps the run paused while another of its steps still waits" do
      other = step_session
      [ @session, other ].each { |s| s.merge_jsonb!(:metadata, "auth_paused_at" => 5.minutes.ago.iso8601) }
      @run.pause!

      AuthPause.new(@session, runtime: @runtime).resume!

      assert_equal "paused", @run.reload.state
    end

    test "types nothing into a session that is not paused" do
      refute AuthPause.new(@session, runtime: @runtime).resume!
      refute_includes @runtime.execs, RESUME_PROMPT_TYPED
    end
  end
end
