# frozen_string_literal: true

require "test_helper"
require "open3"

module Sessions
  # checkpoint.sh and restore.sh run inside agent containers; here they run as they are,
  # with real bash, git, tar and curl. A checkout's work goes into an archive and comes
  # back in a fresh clone of the same remote, as it does for a restored session.
  class CheckpointScriptsTest < ActiveSupport::TestCase
    Output = Struct.new(:lines) do
      def line(tag) = lines.find { |fields| fields.first == tag }
      def repo = line("REPO")
    end

    setup do
      @dir = Dir.mktmpdir("checkpoint-scripts")
      @origin = path("origin.git")
      @archive = path("archive.tgz")
      git(@dir, "init", "-q", "--bare", @origin)
      git(@origin, "symbolic-ref", "HEAD", "refs/heads/main")
      @checkout = path("before/workspace/repo/api")
      git(@dir, "clone", "-q", @origin, @checkout)
      git(@checkout, "symbolic-ref", "HEAD", "refs/heads/main")
      commit(@checkout, "README.md")
      git(@checkout, "push", "-q", "origin", "main")
      FileUtils.mkdir_p([ path("before/home"), path("after/workspace"), path("after/home") ])
    end

    teardown { FileUtils.rm_rf(@dir) }

    # Untracked files are left out: the web image's busybox tar has no --null, which
    # checkpoint.sh needs and the agent image's GNU tar has.
    test "a branch's unpushed commits and uncommitted changes, the workspace and the conversation come back" do
      git(@checkout, "checkout", "-q", "-b", "other")
      other = commit(@checkout, "other.txt")
      git(@checkout, "checkout", "-q", "-b", "feature", "main")
      head = commit(@checkout, "feature.txt")
      File.write(File.join(@checkout, "README.md"), "edited\n")
      File.write(File.join(@checkout, "staged.txt"), "staged\n")
      git(@checkout, "add", "staged.txt")
      write(path("before/workspace/outputs/report.md"), "report\n")
      write(path("before/home/.claude/projects/p/conv-1.jsonl"), "{}\n")

      saved = checkpoint

      assert_equal [ "REPO", "7", "ok", "feature", head, "false", "true", "1", "1" ], saved.repo.first(9)
      assert_equal [ "CONVERSATION", "conv-1" ], saved.line("CONVERSATION")
      assert_equal "1", saved.line("ARCHIVE")[2], "the workspace is in the archive"

      restored = restore(saved)

      assert_equal [ "REPO", "7", "ok" ], restored.repo.first(3)
      assert_equal [ [ "WORKSPACE_OK" ], [ "CONVERSATION_OK" ] ], restored.lines.reject { |fields| fields.first == "REPO" }
      assert_equal "feature", git(@restored, "symbolic-ref", "--short", "HEAD")
      assert_equal head, git(@restored, "rev-parse", "HEAD")
      assert_equal other, git(@restored, "rev-parse", "refs/heads/other")
      assert_equal "edited\n", File.read(File.join(@restored, "README.md"))
      assert_equal "staged\n", File.read(File.join(@restored, "staged.txt"))
      assert_equal "report\n", File.read(path("after/workspace/outputs/report.md"))
      assert_path_exists path("after/home/.claude/projects/p/conv-1.jsonl")
      refute_path_exists path("after/workspace/.aixle-restore")
    end

    test "commits made on top of a branch the remote has come back on that branch" do
      git(@checkout, "checkout", "-q", "-b", "feature")
      commit(@checkout, "pushed.txt")
      git(@checkout, "push", "-q", "origin", "feature")
      head = commit(@checkout, "local.txt")

      saved = checkpoint
      assert_equal [ "feature", head, "true" ], saved.repo[3, 3]

      restored = restore(saved, clone_branch: "feature")

      assert_equal "ok", restored.repo[2]
      assert_equal "feature", git(@restored, "symbolic-ref", "--short", "HEAD")
      assert_equal head, git(@restored, "rev-parse", "HEAD")
    end

    private

    def checkpoint
      run_script(Checkpoint::SCRIPT, "aixle-checkpoint",
          "--url", "file://#{@archive}", "--max-bytes", 1.megabyte, "--upload-timeout", 30,
          "--workspace", path("before/workspace"), "--home", path("before/home"),
          "--conversation-id-command", "ls .claude/projects/p | sed 's/[.]jsonl$//'",
          "--conversation", ".claude/projects", "--repo", 7, @checkout, "--exclude", "./repo")
    end

    # The new session's clone is the recorded branch when the remote has it, as
    # GitCredentials::SessionGitSetup makes it.
    def restore(saved, clone_branch: "main")
      @restored = path("after/workspace/repo/api")
      git(@dir, "clone", "-q", "--branch", clone_branch, @origin, @restored)
      _tag, key, _status, branch, head, on_remote = saved.repo
      run_script(Restore::SCRIPT, "aixle-restore",
          "--url", "file://#{@archive}", "--download-timeout", 30,
          "--workspace", path("after/workspace"), "--home", path("after/home"),
          "--leftovers", path("after/workspace/.aixle-restore"),
          "--repo", key, @restored, branch, head, on_remote)
    end

    def run_script(script, *arguments)
      stdout, stderr, status = Open3.capture3("/bin/bash", "-c", script, *arguments.map(&:to_s))
      assert status.success?, "#{arguments.first} exited #{status.exitstatus}: #{stdout}#{stderr}"
      Output.new(stdout.lines.map { |line| line.chomp.split("\t", -1) })
    end

    def git(dir, *arguments)
      stdout, stderr, status = Open3.capture3("git", "-c", "user.name=QA", "-c", "user.email=qa@example.com",
                                              *arguments, chdir: dir)
      assert status.success?, "git #{arguments.join(' ')}: #{stderr}"
      stdout.strip
    end

    def commit(dir, file)
      write(File.join(dir, file), "#{file}\n")
      git(dir, "add", file)
      git(dir, "commit", "-q", "-m", file)
      git(dir, "rev-parse", "HEAD")
    end

    def write(file, content)
      FileUtils.mkdir_p(File.dirname(file))
      File.write(file, content)
    end

    def path(relative) = File.join(@dir, relative)
  end
end
