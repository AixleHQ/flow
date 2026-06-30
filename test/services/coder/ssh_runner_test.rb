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
      assert_equal command, captured_args[ws_idx + 2], "expected the command verbatim as one token after `--`"
      assert_equal ws_idx + 3, captured_args.length, "expected no extra tokens (no `sh`/`-c`) after the command"
      assert_not_includes captured_args, "sh", "command must not be wrapped in `sh -c`"
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

      assert_equal true, captured_opts[:pgroup]
    end

    test "returns stdout, stderr, exit_code on a normal run" do
      Open3.stub(:popen3, popen3_stub(out: "hi", err: "warn")) do
        result = Coder::SshRunner.new(@integration).exec(workspace_name: "ws-1", command: "echo hi")
        assert_equal 0, result[:exit_code]
        assert_equal "hi", result[:stdout]
        assert_equal "warn", result[:stderr]
        assert_equal false, result[:truncated]
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
        assert result[:stdout].bytesize <= 128
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
        assert result[:stdout].bytesize <= cap, "stdout slice must respect max_bytes"
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
  end
end
