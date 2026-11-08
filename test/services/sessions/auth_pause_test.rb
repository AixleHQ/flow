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

    # One pass of the monitor over the session with only Checks::AuthPause, on the pane the
    # runtime shows (BANNER_PANE, quiet for 5 minutes, unless the test set another).
    # @return [Symbol, nil] the check's outcome
    def observe(session = @session, pane: nil)
      @runtime.set_terminal_pane(pane, last_output_at: 5.minutes.ago) if pane
      Monitor.new(checks: [ Checks::AuthPause ]).visit(session.reload).last&.outcome
    end

    RESUME_PROMPT_TYPED = PaneInput.command(Agents::BaseAdapter::AUTH_RESUME_PROMPT).freeze

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

    # heal! renews the grant, then delivers it to every holder, on a real runtime
    # (FakeRuntime), which test/support/runtime_transaction_guard.rb checks: no
    # runtime call is made inside a database transaction, the renewal's included.
    test "a heal that renews and delivers makes no runtime call inside a database transaction" do
      travel 30.minutes
      stub_request(:post, Agents::ClaudeCodeAdapter::OAUTH_TOKEN_URL)
        .with(body: hash_including("refresh_token" => "rt-1"))
        .to_return(status: 200, body: { access_token: "at-2", refresh_token: "rt-2", expires_in: 28_800 }.to_json,
                   headers: { "Content-Type" => "application/json" })

      assert_equal :resumed, observe

      assert_equal "rt-2", delivered_refresh_token
      assert_empty RuntimeTransactionGuard.take
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

      assert_nil observe(pane: pane)
    end

    test "never pauses a runtime that does not name its expired-login banner" do
      @session.update!(agent_type: "codex")

      assert_nil observe
    end

    test "decides nothing on a pane it could not read" do
      assert_nil observe(pane: "")
    end

    test "fails the step once nobody has signed in again within the limit" do
      @session.merge_jsonb!(:metadata, "auth_paused_at" => (AuthPause.limit + 1.minute).ago.iso8601,
                                       "auth_pause_reason" => "Login expired · Please run /login")

      assert_equal :failed, observe

      @session.reload
      assert_equal "failed", @session.state
      assert_match(/agent authentication failed — Login expired/, @session.error_message)
    end

    # The pass loaded the row before it read the pane; the step started finishing while the
    # read was in flight. The pause is a compare-and-set under the row lock.
    test "does not pause a step that started finishing while the pass read it" do
      @credential.mark_refresh_error!("invalid_grant", permanent: true)
      @runtime.on_next_exec("capture-pane") { TerminalSession.find(@session.id).update!(state: "finishing") }

      assert_equal :taken_over, observe

      refute AuthPause.paused?(@session.reload)
      assert_equal "running", @run.reload.state
    end

    test "does not fail a paused step at the limit once it was unpaused meanwhile" do
      @session.merge_jsonb!(:metadata, "auth_paused_at" => (AuthPause.limit + 1.minute).ago.iso8601)
      @runtime.on_next_exec("capture-pane") do
        TerminalSession.find(@session.id).remove_jsonb_keys!(:metadata, *AuthPause::PAUSE_KEYS)
      end

      assert_equal :taken_over, observe

      assert_equal "ready", @session.reload.state
      assert_nil @session.error_message
    end

    test "lets a paused step go once the banner has left its pane" do
      @session.merge_jsonb!(:metadata, "auth_paused_at" => 5.minutes.ago.iso8601)
      @run.pause!

      assert_equal :resumed, observe(pane: "● tick-12\n● tick-13\n> \n")
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

    # A person may be typing there.
    test "types nothing into an interactive session whose login is back, and says so on its page" do
      session = create(:terminal_session, :running, session_type: "agent_session", user: @user, project: @project,
                                                    company: @company, agent_type: "claude_code", container_id: "ctr-i")
      session.merge_jsonb!(:metadata, "auth_paused_at" => 5.minutes.ago.iso8601)

      assert AuthPause.new(session, runtime: @runtime).resume!

      refute_includes @runtime.execs, RESUME_PROMPT_TYPED
      refute AuthPause.paused?(session.reload)
      assert session.metadata["auth_renewed_at"].present?
    end

    test "types nothing into a session that is not paused" do
      refute AuthPause.new(@session, runtime: @runtime).resume!
      refute_includes @runtime.execs, RESUME_PROMPT_TYPED
    end

    # A heal hands the grant to every holder of the credential, each through its
    # own runtime (ContainerRuntime.for_session): a runner holder's goes to its
    # machine, a hosted holder's to the hosted runtime.
    test "a heal writes a runner holder through its machine and a hosted holder through the hosted runtime" do
      runner = create(:runner, :manual, company: @company, created_by: @user)
      machine = create(:runner_environment, runner: runner)
      runner_holder = create(:runner_session, environment: machine, user: @user, company: @company, project: @project,
                                              agent_type: "claude_code", state: "ready", started_at: 1.hour.ago,
                                              container_id: "aixle-#{machine.key}-runner")
      machine.update!(current_session: runner_holder)
      ContainerRuntime::FakeHostRunner.identify!(runner_holder, runner_holder.container_id)
      host_runner = ContainerRuntime::FakeHostRunner.new(machine)
      host_runner.machine.start(runner_holder.id)

      assert_equal :resumed, observe

      assert_equal "rt-1", delivered_refresh_token, "the paused hosted session took it through the hosted runtime"
      write = host_runner.operations.find { |op| op[:op] == "write_file" }
      assert write, "the runner holder was written through its machine: #{host_runner.ops.inspect}"
      assert_equal runner_holder.id, write[:session_id]
      written = host_runner.machine.container.files["/home/claude/.claude/.credentials.json"]
      assert_equal "rt-1", JSON.parse(written).dig("claudeAiOauth", "refreshToken")
    ensure
      host_runner&.stop
    end
  end
end
