# frozen_string_literal: true

require "test_helper"

module Sessions
  class RestoreTest < ActiveSupport::TestCase
    include CheckpointStorageHelper

    setup do
      @user = create(:user, :with_company)
      @project = create(:project, owner: @user, company: @user.companies.first)
      @origin = create(:terminal_session, :agent_session, user: @user, project: @project, mode: "interactive",
                                                          state: "suspended", suspended_at: 1.day.ago,
                                                          restore_expires_at: 29.days.from_now,
                                                          requested_model: "claude-opus-5-5")
      use_checkpoint_storage
      @cli_version = AgentRuntime.fetch("claude_code").cli_version
      create_checkpoint(@origin, manifest: {
        "conversation_id" => "eb395f2d-d96b-4a6f-ad6c-0ff7c1de7029", "cli_version" => @cli_version,
        "repos" => [ { "repository_id" => 7, "path" => "/workspace/repo/api", "branch" => "feature/x",
                       "head_sha" => "abc123", "on_remote" => false } ]
      })
      @session = create(:terminal_session, :running, :agent_session, user: @user, project: @project,
                                                                     mode: "interactive", restored_from_session: @origin)
      @runtime = ContainerRuntime::FakeRuntime.new
      @container = @runtime.resolve_container("abc123")
      @adapter = Agents::ClaudeCodeAdapter.new
    end

    teardown { restore_checkpoint_storage }

    def restore(stdout: "WORKSPACE_OK\nCONVERSATION_OK\nREPO\t7\tok\n", exit_code: 0)
      @runtime.answer_exec("aixle-restore", stdout: stdout, exit_code: exit_code)
      Restore.new(session: @session, container: @container, runtime: @runtime, adapter: @adapter).call
    end

    def launch_command
      Restore.launch_command(@session.reload, @adapter, mode: "interactive", model: nil, effort: nil)
    end

    test "the new session's configuration is the suspended one's, without what has gone" do
      kept = create(:skill, scope: @project)
      gone = create(:skill, scope: @project, archived_at: 1.hour.ago)
      @origin.update!(skill_ids: [ kept.id, gone.id ], metadata: { "aixle_builder" => true, "vscode_token" => "x" })

      params = Restore.params_for(@origin)

      assert_equal [ kept.id ], params[:skill_ids]
      assert_equal @origin.id, params[:restored_from_session_id]
      assert_equal "claude-opus-5-5", params[:requested_model]
      assert params[:metadata]["aixle_builder"]
      refute params[:metadata].key?("vscode_token")
      assert_match(/"#{gone.name}" is no longer available/, params[:metadata]["restore"]["notes"].join)
    end

    test "a conversation saved by the same CLI version is resumed" do
      restore

      state = @session.reload.metadata["restore"]
      assert state["resume"]
      assert_equal "claude --resume eb395f2d-d96b-4a6f-ad6c-0ff7c1de7029", launch_command
    end

    test "the script fetches the archive and restores each repository the checkpoint names" do
      restore

      script = @runtime.execs.find { |cmd| cmd.last.to_s.include?("aixle-restore") }.last
      assert_includes script, "https://bucket.test/store/"
      assert_includes script, "restore_repo 7 /workspace/repo/api feature/x abc123 false"
      assert_includes script, "tar -C /home/claude -xf"
    end

    # Each CLI keeps its conversation in an internal format, and an upgrade may not read
    # an older one.
    test "a conversation saved by another CLI version starts fresh, and the notice says why" do
      @origin.session_checkpoint.update!(manifest: @origin.session_checkpoint.manifest.merge("cli_version" => "0.0.1"))

      restore

      refute @session.reload.metadata.dig("restore", "resume")
      assert_equal "claude", launch_command
      assert_match(/changed from 0\.0\.1/, @session.metadata.dig("restore", "notes").join)
    end

    test "work that could not be put back is left where the notice says" do
      restore(stdout: "WORKSPACE_OK\nCONVERSATION_OK\nREPO\t7\tbundle_failed\n")

      notes = @session.reload.metadata.dig("restore", "notes").join
      assert_includes notes, "Unpushed commits of /workspace/repo/api could not be put back"
      assert_includes notes, "/workspace/.aixle-restore/7.bundle"
    end

    test "the restore notice is appended to the agent's context file" do
      restore(stdout: "WORKSPACE_OK\nCONVERSATION_OK\nREPO\t7\tpatch_failed\n")

      append = @runtime.execs.find { |cmd| cmd.last.to_s.include?("base64 -d >> /home/claude/.claude/CLAUDE.md") }
      assert append, "the notice is written into the context file"
      text = Base64.decode64(append.last[/echo (\S+) \| base64/, 1])
      assert_includes text, "This session was restored"
      assert_includes text, "continues session ##{@origin.id}"
      assert_includes text, "Uncommitted changes of /workspace/repo/api could not be applied"
    end

    test "an archive that could not be fetched starts a fresh conversation, not a failed session" do
      restore(stdout: "DOWNLOAD_FAILED\n", exit_code: 5)

      refute @session.reload.metadata.dig("restore", "resume")
      assert_equal "claude", launch_command
      assert_match(/could not be unpacked \(DOWNLOAD_FAILED\)/, @session.metadata.dig("restore", "notes").join)
    end

    test "a session that is not a restore starts the CLI as usual" do
      plain = create(:terminal_session, :running, :agent_session, user: @user, project: @project)

      assert_equal "claude", Restore.launch_command(plain, @adapter, mode: "interactive", model: nil, effort: nil)
    end
  end
end
