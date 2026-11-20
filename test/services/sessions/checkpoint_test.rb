# frozen_string_literal: true

require "test_helper"

module Sessions
  class CheckpointTest < ActiveSupport::TestCase
    include CheckpointStorageHelper

    setup do
      @user = create(:user, :with_company)
      @project = create(:project, owner: @user, company: @user.companies.first)
      @session = create(:terminal_session, :running, :agent_session, user: @user, project: @project,
                                                                     mode: "interactive", state: "ready",
                                                                     metadata: { "repository_paths" => { "7" => "/workspace/repo/api" } })
      @runtime = ContainerRuntime::FakeRuntime.new
      @container = @runtime.resolve_container("abc123")
      use_checkpoint_storage(archive: "archive-bytes")
    end

    teardown { restore_checkpoint_storage }

    def take(adapter: Agents::ClaudeCodeAdapter.new)
      Checkpoint.new(session: @session, container: @container, runtime: @runtime, adapter: adapter).call
    end

    # What the container's script prints is the whole interface: the fake states it.
    def script_prints(stdout, exit_code: 0)
      @runtime.answer_exec("aixle-checkpoint", stdout: stdout, exit_code: exit_code)
    end

    test "records what the container saved and stores the archive it uploaded" do
      script_prints("REPO\t7\tok\tfeature/x\tabc123\tfalse\ttrue\t1\t1\t0\n" \
                    "CONVERSATION\teb395f2d-d96b-4a6f-ad6c-0ff7c1de7029\nARCHIVE\t13\t1\n")

      checkpoint = take

      assert_equal 13, checkpoint.byte_size
      assert_equal "eb395f2d-d96b-4a6f-ad6c-0ff7c1de7029", checkpoint.conversation_id
      assert_equal AgentRuntime.fetch("claude_code").cli_version, checkpoint.cli_version
      assert checkpoint.workspace_included?
      assert_equal [ { "repository_id" => 7, "path" => "/workspace/repo/api", "branch" => "feature/x",
                       "head_sha" => "abc123", "on_remote" => false, "dirty" => true,
                       "bundle" => true, "patch" => true, "untracked" => false } ], checkpoint.repos
      assert_equal "archive-bytes", checkpoint.reload.archive.read
      assert_equal :store, checkpoint.archive.storage_key
    end

    test "the script saves the session's repositories and the CLI's conversation, and leaves the rest out" do
      script_prints("ARCHIVE\t1\t1\n")

      take

      script = @runtime.execs.last.last
      assert_includes script, "repo 7 /workspace/repo/api"
      assert_includes script, "cd /home/claude"
      assert_includes script, ".claude/projects"
      %w[./repo ./assets ./.mcp.json ./.aixle node_modules .venv].each do |excluded|
        assert_includes script, "--exclude=#{excluded}"
      end
      assert_match %r{curl .*-X PUT -T "\$D\.tgz" https://bucket\.test/cache/}, script
    end

    # Cursor reads its context from /workspace/AGENTS.md, which the new session writes again.
    test "a context file kept in /workspace is not carried over" do
      script_prints("ARCHIVE\t1\t1\n")

      take(adapter: Agents::CursorCliAdapter.new)

      assert_includes @runtime.execs.last.last, "--exclude=./AGENTS.md"
    end

    test "an archive that was dropped down to the conversation and git work says so" do
      script_prints("CONVERSATION\t\nARCHIVE\t9\t0\n")

      checkpoint = take

      refute_predicate checkpoint, :workspace_included?
      assert_nil checkpoint.conversation_id
    end

    test "a failed upload leaves no checkpoint" do
      script_prints("UPLOAD_FAILED\n", exit_code: 4)

      error = assert_raises(Checkpoint::Failed) { take }

      assert_match(/UPLOAD_FAILED/, error.message)
      assert_equal 0, SessionCheckpoint.count
    end
  end
end
