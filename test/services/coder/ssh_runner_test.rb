# frozen_string_literal: true

require "test_helper"

module Coder
  class SshRunnerTest < ActiveSupport::TestCase
    setup do
      @company     = create(:company)
      @user        = create(:user, :admin, company: @company)
      @integration = create(:integration, :coder, :active, company: @company, connected_by: @user)
      @token       = @integration.credentials_data["session_token"]
    end

    # Minimal wait_thr stub compatible with the real popen3 wait_thr — exposes
    # `value`, `pid`, and `alive?` so the timeout/kill path can be exercised.
    class StubWaitThr
      attr_reader :pid

      def initialize(exitstatus:, pid: 99_999, alive: false)
        @value = Struct.new(:exitstatus).new(exitstatus)
        @pid   = pid
        @alive = alive
      end

      def value
        @alive = false
        @value
      end

      def alive?
        @alive
      end
    end

    # Returns the popen3 stub lambda. Any kwargs (`pgroup: true`) are accepted
    # and ignored — production code passes `pgroup: true` for child-process-
    # group control on the real CLI; tests don't fork.
    def popen3_stub(out: "", err: "", exit_code: 0, alive: false, pid: 99_999, &capture)
      lambda { |env, *argv, **_opts, &blk|
        capture&.call(env, argv)
        in_r  = StringIO.new
        out_r = StringIO.new(out)
        err_r = StringIO.new(err)
        wait  = StubWaitThr.new(exitstatus: exit_code, alive: alive, pid: pid)
        blk.call(in_r, out_r, err_r, wait)
      }
    end

    test "passes the session token via env, never via argv" do
      captured_args = nil
      captured_env  = nil
      stub = popen3_stub(out: "hello") do |env, argv|
        captured_env  = env
        captured_args = argv
      end

      Open3.stub(:popen3, stub) do
        runner = Coder::SshRunner.new(@integration)
        runner.exec(workspace_name: "ws-1", command: "echo hello")
      end

      assert_equal @token, captured_env["CODER_SESSION_TOKEN"]
      assert_equal @integration.coder_url, captured_env["CODER_URL"]
      assert_includes captured_args, "coder"
      assert_includes captured_args, "ws-1"
      assert_not_includes captured_args, @token
    end

    # Regression guard: the canonical invocation is
    # `coder ssh <workspace> -- <command>` (coder-instructions.md §8, e.g.
    # `coder ssh alex -- ps aux`). Two things matter and are both asserted here:
    #
    #   1. The `--` separator must sit immediately after the workspace name —
    #      without it the CLI rejects the trailing tokens (`wanted 1 args but
    #      got N` / `No containers found!`), which broke coder_ssh_exec
    #      end-to-end (task #284, asset wf_output_20260623-1-7hx199.md).
    #   2. The command must be the SINGLE token right after `--` — NOT wrapped
    #      in `sh -c`. `coder ssh` space-joins its post-`--` argv before
    #      forwarding to the remote login shell, so an extra `sh -c` wrapper
    #      collapses the boundaries and corrupts any quoting inside the command
    #      (e.g. `echo "a b"` ran as an empty `echo`). See issue-coder-ssh-exec.md.
    test "passes `--` then the command as a single token (no `sh -c` wrapper)" do
      captured_args = nil
      stub = popen3_stub { |_env, argv| captured_args = argv }

      command = 'echo "a b"; whoami'
      Open3.stub(:popen3, stub) do
        Coder::SshRunner.new(@integration).exec(workspace_name: "ws-x", command: command)
      end

      ws_idx = captured_args.index("ws-x")
      assert ws_idx, "expected workspace name to appear in argv"
      assert_equal "--", captured_args[ws_idx + 1], "expected `--` immediately after workspace name"
      remote = captured_args[ws_idx + 2]
      assert remote.end_with?(command), "expected the command verbatim at the end of the single remote token"
      assert_equal ws_idx + 3, captured_args.length, "expected no extra tokens (no `sh`/`-c`) after the command"
      assert_not_includes captured_args, "sh", "command must not be wrapped in `sh -c`"
    end

    # `coder ssh <ws> -- <cmd>` inherits almost no environment; without HOME
    # every git call on the workspace dies with `fatal: $HOME not set`, which
    # sessions were working around by hand-prefixing each command.
    test "exports a HOME fallback ahead of the command" do
      captured_args = nil
      stub = popen3_stub { |_env, argv| captured_args = argv }

      Open3.stub(:popen3, stub) do
        Coder::SshRunner.new(@integration).exec(workspace_name: "ws-1", command: "git status")
      end

      remote = captured_args.last
      assert_match(/\Aexport HOME=/, remote)
      assert_match(%r{/tmp}, remote, "expected a fallback for an agent that cannot write to /root")
      assert remote.end_with?("git status")
    end

    # Regression guard: protect the well-known popen3 + Timeout anti-pattern by
    # confirming the child is spawned with `pgroup: true` so the negative-pid
    # signal can reap orphaned `coder ssh` subprocesses on timeout.
    test "spawns the child with a dedicated process group" do
      captured_opts = nil
      capturing_stub = lambda { |_env, *_argv, **opts, &blk|
        captured_opts = opts
        in_r  = StringIO.new
        out_r = StringIO.new("")
        err_r = StringIO.new("")
        wait  = StubWaitThr.new(exitstatus: 0)
        blk.call(in_r, out_r, err_r, wait)
      }

      Open3.stub(:popen3, capturing_stub) do
        Coder::SshRunner.new(@integration).exec(workspace_name: "ws-1", command: "true")
      end

      assert captured_opts[:pgroup]
    end

    test "returns stdout, stderr, exit_code on a normal run" do
      Open3.stub(:popen3, popen3_stub(out: "hi", err: "warn")) do
        result = Coder::SshRunner.new(@integration).exec(workspace_name: "ws-1", command: "echo hi")
        assert_equal 0, result[:exit_code]
        assert_equal "hi", result[:stdout]
        assert_equal "warn", result[:stderr]
        refute result[:truncated]
      end
    end

    test "redacts the session token from stdout/stderr output" do
      Open3.stub(:popen3, popen3_stub(out: "here is the token: #{@token}")) do
        result = Coder::SshRunner.new(@integration).exec(workspace_name: "ws-1", command: "echo hi")
        assert_no_match(/#{Regexp.escape(@token)}/, result[:stdout])
        assert_match(/\[REDACTED\]/, result[:stdout])
      end
    end

    test "truncates the response when over the max-bytes budget" do
      big = "X" * 1024
      Open3.stub(:popen3, popen3_stub(out: big)) do
        result = Coder::SshRunner.new(@integration).exec(workspace_name: "ws-1", command: "noop", max_bytes: 128)
        assert result[:truncated]
        assert_equal 1024, result[:stdout_bytes_total]
        assert_operator result[:stdout].bytesize, :<=, 128
      end
    end

    # DD-15: the bounded reader must stop pulling from the pipe once the
    # truncation budget is exceeded, instead of buffering an unbounded amount
    # of remote output before truncation runs.
    test "bounded reader stops pulling once max_bytes is exceeded" do
      cap        = 256
      slow_pipe  = Class.new do
        def initialize(total); @remaining = total; @chunk = "Y" * 4096; end
        attr_reader :reads_served
        def read(n = nil)
          n ||= @chunk.bytesize
          return nil if @remaining <= 0
          give = [ n, @chunk.bytesize, @remaining ].min
          @remaining -= give
          @reads_served = (@reads_served || 0) + 1
          @chunk.byteslice(0, give)
        end
        def closed?; @remaining <= 0; end
      end

      # Effectively-infinite source: 32 MiB available. If the reader did not
      # respect the cap it would read all 32 MiB.
      huge_source = slow_pipe.new(32 * 1024 * 1024)
      stub = lambda { |_env, *_argv, **_opts, &blk|
        in_r  = StringIO.new
        err_r = StringIO.new("")
        wait  = StubWaitThr.new(exitstatus: 0)
        blk.call(in_r, huge_source, err_r, wait)
      }

      Open3.stub(:popen3, stub) do
        result = Coder::SshRunner.new(@integration).exec(workspace_name: "ws-1", command: "yes", max_bytes: cap)
        assert result[:truncated]
        assert_operator result[:stdout].bytesize, :<=, cap, "stdout slice must respect max_bytes"
      end

      # The bounded reader should have stopped well under the source size — a
      # handful of READ_CHUNK_BYTES (16 KiB) chunks, not thousands.
      assert huge_source.reads_served && huge_source.reads_served < 16,
             "bounded reader did not stop early (#{huge_source.reads_served} chunks pulled)"
    end

    # DD-15: on timeout, the child process group must be signalled — otherwise
    # the underlying `coder ssh` and its remote command are orphaned.
    test "kills the process group on timeout instead of leaking the child" do
      signals = []
      original_grace = Coder::SshRunner.kill_grace_seconds
      Coder::SshRunner.kill_grace_seconds = 0.0

      begin
        Process.stub(:kill, ->(sig, pid) { signals << [ sig, pid ] }) do
          # popen3 stub: simulate a child whose pipes never close — the bounded
          # reader will sit waiting on read(...) until the runner kills it.
          slow_stub = lambda { |_env, *_argv, **_opts, &blk|
            in_r, in_w = IO.pipe
            out_r, _out_w = IO.pipe
            err_r, _err_w = IO.pipe
            wait = StubWaitThr.new(exitstatus: 124, pid: 424_242, alive: false)
            begin
              blk.call(in_w, out_r, err_r, wait)
            ensure
              [ in_r, in_w, out_r, err_r ].each { |io| io.close unless io.closed? }
            end
          }

          Open3.stub(:popen3, slow_stub) do
            result = Coder::SshRunner.new(@integration).exec(
              workspace_name: "ws-1", command: "sleep 999", timeout: 1
            )
            assert_equal 124, result[:exit_code]
            assert_match(/timed out/, result[:stderr])
          end
        end
      ensure
        Coder::SshRunner.kill_grace_seconds = original_grace
      end

      assert signals.any? { |sig, pid| sig == "-TERM" && pid == 424_242 },
             "expected SIGTERM to the process group on timeout; got #{signals.inspect}"
    end

    test "returns exit_code 127 with a useful message when the CLI is missing" do
      Open3.stub(:popen3, ->(*_args, **_opts, &_blk) { raise Errno::ENOENT }) do
        result = Coder::SshRunner.new(@integration).exec(workspace_name: "ws-1", command: "echo hi")
        assert_equal 127, result[:exit_code]
        assert_match(/coder ssh: command not found/, result[:stderr])
      end
    end

    test "rejects empty command and workspace name" do
      runner = Coder::SshRunner.new(@integration)
      assert_raises(Coder::SshRunner::CommandError) { runner.exec(workspace_name: "", command: "x") }
      assert_raises(Coder::SshRunner::CommandError) { runner.exec(workspace_name: "ws", command: "  ") }
    end

    # ---------- detached execution ----------

    test "detached start writes the command through a quoted heredoc and returns a job id" do
      captured_args = nil
      stub = popen3_stub(out: "aixle_job job_id=abc123 job_dir=/var/lib/aixle-jobs\n") do |_env, argv|
        captured_args = argv
      end

      result = Open3.stub(:popen3, stub) do
        Coder::SshRunner.new(@integration).exec_detached(
          workspace_name: "ws-1", command: "make check_all", job_id: "abc123"
        )
      end

      assert_equal "abc123", result[:job_id]
      assert_equal "/var/lib/aixle-jobs", result[:job_dir]
      assert_equal "/var/lib/aixle-jobs/abc123.log", result[:log_path]

      script = captured_args.last
      assert_match(/make check_all/, script, "expected the command to reach the remote script verbatim")
      assert_match(/setsid/, script)
      assert_match(/nohup/, script, "expected a fallback for a workspace without setsid")
      assert_match(%r{TMPDIR:-/tmp}, script, "expected a fallback job dir when /var/lib is not writable")
    end

    # A secret belongs in the launcher, which travels over SSH and is never
    # written down — not in the `<job_id>.cmd` file, which stays on a workspace
    # that outlives the session.
    test "detached start exports env in the launcher, never into the command file" do
      captured_args = nil
      stub = popen3_stub(out: "aixle_job job_id=j1 job_dir=/var/lib/aixle-jobs\n") do |_env, argv|
        captured_args = argv
      end

      Open3.stub(:popen3, stub) do
        Coder::SshRunner.new(@integration).exec_detached(
          workspace_name: "ws-1",
          command:        'git clone "$URL"',
          job_id:         "j1",
          env:            { "AIXLE_GH_TOKEN" => "ghs_secret" }
        )
      end

      script = captured_args.last
      launcher, _, command_file = script.partition("cat > \"$BASE.cmd\"")

      assert_match(/AIXLE_GH_TOKEN='ghs_secret'; export AIXLE_GH_TOKEN/, launcher)
      assert_no_match(/ghs_secret/, command_file, "the secret must not reach the job's command file")
    end

    test "detached start rejects an env name that is not a shell identifier" do
      assert_raises(Coder::SshRunner::CommandError) do
        Coder::SshRunner.new(@integration).exec_detached(
          workspace_name: "ws-1", command: "true", env: { "TOKEN; rm -rf /" => "x" }
        )
      end
    end

    test "detached start reports the fallback job dir chosen by the workspace" do
      stub = popen3_stub(out: "aixle_job job_id=j1 job_dir=/tmp/aixle-jobs\n")

      result = Open3.stub(:popen3, stub) do
        Coder::SshRunner.new(@integration).exec_detached(workspace_name: "ws-1", command: "true", job_id: "j1")
      end

      assert_equal "/tmp/aixle-jobs/j1.log", result[:log_path]
    end

    test "detached start raises when the workspace could not launch the job" do
      stub = popen3_stub(err: "cannot create a job directory", exit_code: 1)

      Open3.stub(:popen3, stub) do
        error = assert_raises(Coder::SshRunner::CommandError) do
          Coder::SshRunner.new(@integration).exec_detached(workspace_name: "ws-1", command: "true")
        end
        assert_match(/cannot create a job directory/, error.message)
      end
    end

    test "job status parses state, exit code and log tail" do
      out = "aixle_job state=exited exit_code=2\n---aixle_job_log---\nline one\nline two\n"

      status = Open3.stub(:popen3, popen3_stub(out: out)) do
        Coder::SshRunner.new(@integration).job_status(workspace_name: "ws-1", job_id: "j1")
      end

      assert_equal "exited", status[:state]
      assert_equal 2, status[:exit_code]
      assert_equal "line one\nline two\n", status[:tail]
    end

    test "job status reports unknown for a job the workspace has no trace of" do
      status = Open3.stub(:popen3, popen3_stub(out: "aixle_job state=unknown exit_code=\n")) do
        Coder::SshRunner.new(@integration).job_status(workspace_name: "ws-1", job_id: "gone")
      end

      assert_equal "unknown", status[:state]
      assert_nil status[:exit_code]
    end

    test "job id must be a safe token" do
      runner = Coder::SshRunner.new(@integration)
      assert_raises(Coder::SshRunner::CommandError) do
        runner.job_status(workspace_name: "ws-1", job_id: "j1; rm -rf /")
      end
      assert_raises(Coder::SshRunner::CommandError) do
        runner.exec_detached(workspace_name: "ws-1", command: "true", job_id: "../../etc/passwd")
      end
    end

    # ---------- honest timeouts ----------

    test "clamps the requested timeout to the transport ceiling it can actually reach" do
      slow = lambda { |_env, *_argv, **_opts, &blk|
        in_r  = StringIO.new
        out_r = Object.new
        def out_r.read(*) = sleep(5)
        err_r = StringIO.new("")
        wait  = StubWaitThr.new(exitstatus: 0, pid: 4242, alive: true)
        blk.call(in_r, out_r, err_r, wait)
      }

      with_settings_ceiling(1) do
        Process.stub(:kill, ->(*_args) { 1 }) do
          Open3.stub(:popen3, slow) do
            result = Coder::SshRunner.new(@integration).exec(
              workspace_name: "ws-1", command: "sleep 999", timeout: 600
            )

            assert_equal 124, result[:exit_code]
            assert_match(/timed out after 1s/, result[:stderr],
                         "expected the ceiling to win over the requested 600s")
          end
        end
      end
    end

    test "a timeout says the remote work may still be running and must not be re-issued" do
      slow = lambda { |_env, *_argv, **_opts, &blk|
        in_r  = StringIO.new
        out_r = Object.new
        def out_r.read(*) = sleep(5)
        err_r = StringIO.new("")
        wait  = StubWaitThr.new(exitstatus: 0, pid: 4242, alive: true)
        blk.call(in_r, out_r, err_r, wait)
      }

      Process.stub(:kill, ->(*_args) { 1 }) do
        Open3.stub(:popen3, slow) do
          result = Coder::SshRunner.new(@integration).exec(
            workspace_name: "ws-1", command: "make check_all", timeout: 1
          )

          assert_match(/still be RUNNING/, result[:stderr])
          assert_match(/detach: true/, result[:stderr])
        end
      end
    end

    private

    def with_settings_ceiling(seconds)
      original = Settings.coder.ssh_exec_ceiling_seconds
      Settings.coder.ssh_exec_ceiling_seconds = seconds
      yield
    ensure
      Settings.coder.ssh_exec_ceiling_seconds = original
    end
  end
end
