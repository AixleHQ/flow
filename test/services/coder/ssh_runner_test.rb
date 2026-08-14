# frozen_string_literal: true

require "test_helper"
require "tmpdir"

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

    # The launch metadata has to be on disk *before* the wrapper starts, or a job
    # killed a second later has nothing to identify it (task #581). The traps and
    # the heartbeat are what a `died` job is dated and explained by, and neither
    # is observable from the outside once the wrapper is gone — so they are
    # asserted on the script that gets written.
    test "detached start persists launch metadata before it starts the wrapper" do
      captured_args = nil
      stub = popen3_stub(
        out: "aixle_job job_id=j1 job_dir=/var/lib/aixle-jobs started_at=2026-08-14T10:00:00Z\n"
      ) { |_env, argv| captured_args = argv }

      result = Open3.stub(:popen3, stub) do
        Coder::SshRunner.new(@integration).exec_detached(
          workspace_name: "ws-1", command: "make check_all", job_id: "j1"
        )
      end

      assert_equal "2026-08-14T10:00:00Z", result[:started_at]
      assert_equal "/var/lib/aixle-jobs/j1.meta", result[:meta_path]

      script       = captured_args.last
      before_start = script.split("chmod +x").first

      assert_match(/job_id=j1/, before_start)
      assert_match(/workspace=ws-1/, before_start)
      assert_match(/started_at=\$AIXLE_STARTED_AT/, before_start)
      assert_match(/> "\$BASE\.meta"/, before_start, "metadata must be written before the wrapper is launched")

      assert_match(/trap '.*TERM 143' TERM/, script, "a terminated wrapper must still record its outcome")
      assert_match(/reason=\$2/, script)
      assert_match(/"\$BASE\.hb"/, script, "expected a heartbeat to date a job that cannot record its own end")
    end

    # The wrapper must send the command the signal it was itself sent — a
    # recorded `signal=INT` next to a command that was really sent TERM is
    # exactly the misleading evidence this feature exists to remove.
    test "the wrapper forwards the received signal rather than always sending TERM" do
      captured_args = nil
      stub = popen3_stub(out: "aixle_job job_id=j1 job_dir=/var/lib/aixle-jobs\n") { |_env, argv| captured_args = argv }

      Open3.stub(:popen3, stub) do
        Coder::SshRunner.new(@integration).exec_detached(workspace_name: "ws-1", command: "sleep 30", job_id: "j1")
      end

      script = captured_args.last

      assert_match(/kill -s "\$1" "\$AIXLE_CHILD"/, script,
                   "the trap must forward the signal it received, not a hard-coded TERM")
      assert_match(/INT\|QUIT/, script,
                   "INT/QUIT are ignored by a background child (POSIX) and need the TERM follow-up")
      assert_match(/child_signal=TERM/, script,
                   "a delivered signal that differs from the received one must be recorded")
    end

    # A workspace name is recorded inside a double-quoted shell string; a name
    # carrying shell metacharacters must not become command substitution.
    test "detached start neutralises shell metacharacters in the recorded workspace name" do
      captured_args = nil
      stub = popen3_stub(out: "aixle_job job_id=j1 job_dir=/var/lib/aixle-jobs\n") { |_env, argv| captured_args = argv }

      Open3.stub(:popen3, stub) do
        Coder::SshRunner.new(@integration).exec_detached(
          workspace_name: 'ws-1"; $(id > /tmp/pwned); echo "', command: "true", job_id: "j1"
        )
      end

      recorded = captured_args.last[/echo "workspace=(.*)"$/, 1]

      assert_match(/\A[A-Za-z0-9._-]+\z/, recorded,
                   "the recorded workspace name must not carry shell syntax; got #{recorded.inspect}")
      assert_no_match(/pwned\)/, recorded)
    end

    test "job status parses state, exit code and log tail" do
      out = "aixle_job state=exited exit_code=2\n---aixle_job_log---\nline one\nline two\n"

      status = Open3.stub(:popen3, popen3_stub(out: out)) do
        Coder::SshRunner.new(@integration).job_status(workspace_name: "ws-1", job_id: "j1")
      end

      assert_equal "exited", status[:state]
      assert_equal 2, status[:exit_code]
      assert_equal "line one\nline two\n", status[:tail]
      assert_not status.key?(:result)
    end

    # How a detached job hands facts back to whoever polls it — the checked-out
    # commit of a repo bootstrap is only knowable here.
    test "job status parses the structured result block a job printed" do
      out = "aixle_job state=exited exit_code=0\n---aixle_job_log---\n" \
            "cloning\n---aixle_job_result---\nhead_sha=abc123\nworktree=clean\nrequested_ref=\n"

      status = Open3.stub(:popen3, popen3_stub(out: out)) do
        Coder::SshRunner.new(@integration).job_status(workspace_name: "ws-1", job_id: "j1")
      end

      assert_equal({ "head_sha" => "abc123", "worktree" => "clean", "requested_ref" => "" }, status[:result])
      assert_match(/cloning/, status[:tail])
    end

    test "job status keeps the last result block when a job printed more than one" do
      out = "aixle_job state=exited exit_code=0\n---aixle_job_log---\n" \
            "---aixle_job_result---\nhead_sha=stale\n---aixle_job_result---\nhead_sha=fresh\n"

      status = Open3.stub(:popen3, popen3_stub(out: out)) do
        Coder::SshRunner.new(@integration).job_status(workspace_name: "ws-1", job_id: "j1")
      end

      assert_equal "fresh", status[:result]["head_sha"]
    end

    test "job status reports unknown for a job the workspace has no trace of" do
      status = Open3.stub(:popen3, popen3_stub(out: "aixle_job state=unknown exit_code=\n")) do
        Coder::SshRunner.new(@integration).job_status(workspace_name: "ws-1", job_id: "gone")
      end

      assert_equal "unknown", status[:state]
      assert_nil status[:exit_code]
    end

    # ---------- lifecycle metadata and diagnosis (task #581) ----------

    test "job status returns the lifecycle metadata of a job that finished normally" do
      out = job_status_output(
        header: "state=exited exit_code=0",
        meta:   <<~META,
          job_id=j1
          workspace=ws-1
          job_dir=/var/lib/aixle-jobs
          log_path=/var/lib/aixle-jobs/j1.log
          started_at=2026-08-14T10:00:00Z
          started_at_epoch=1786701600
          heartbeat_interval_seconds=10
          pid=4242
          pgid=4242
          finished_at=2026-08-14T10:02:03Z
          finished_at_epoch=1786701723
          reason=completed
          exit_code=0
          checked_at=2026-08-14T10:05:00Z
          checked_at_epoch=1786701900
          log_bytes=64
        META
        command: "make check_all",
        log:     "3 files inspected\n"
      )

      status = Open3.stub(:popen3, popen3_stub(out: out)) do
        Coder::SshRunner.new(@integration).job_status(workspace_name: "ws-1", job_id: "j1")
      end

      assert_equal "exited", status[:state]
      assert_equal 0, status[:exit_code]
      assert_equal "completed", status[:reason]
      assert_equal "ws-1", status[:workspace]
      assert_equal "make check_all", status[:command]
      assert_equal 4242, status[:pid]
      assert_equal 4242, status[:pgid]
      assert_equal "2026-08-14T10:00:00Z", status[:started_at]
      assert_equal "2026-08-14T10:02:03Z", status[:finished_at]
      assert_equal 123, status[:elapsed_seconds]
      assert_equal 64, status[:log_bytes]
      assert_equal "/var/lib/aixle-jobs/j1.log", status[:log_path]
      assert_equal "3 files inspected\n", status[:tail]
      assert_nil status[:finished_at_estimated], "a job that dated itself must not be reported as an estimate"
      assert_match(/completed successfully after 123s/, status[:diagnosis])
    end

    # The distinction the whole feature exists for: a non-zero exit is the
    # command's own verdict, and must not read as an infrastructure failure.
    test "job status reports a non-zero exit as the command's own failure" do
      out = job_status_output(
        header: "state=exited exit_code=3",
        meta:   <<~META,
          started_at=2026-08-14T10:00:00Z
          started_at_epoch=1786701600
          pid=4242
          finished_at=2026-08-14T10:00:20Z
          finished_at_epoch=1786701620
          reason=command_failed
          exit_code=3
          checked_at_epoch=1786701900
        META
        command: "bin/rails test",
        log:     "2 failures\n"
      )

      status = Open3.stub(:popen3, popen3_stub(out: out)) do
        Coder::SshRunner.new(@integration).job_status(workspace_name: "ws-1", job_id: "j1")
      end

      assert_equal "exited", status[:state]
      assert_equal 3, status[:exit_code]
      assert_equal "command_failed", status[:reason]
      assert_equal 20, status[:elapsed_seconds]
      assert_nil status[:signal]
      assert_match(/exited 3/, status[:diagnosis])
      assert_match(/not an infrastructure problem/, status[:diagnosis])
    end

    test "job status reports a trapped signal as a cancellation, not a command failure" do
      out = job_status_output(
        header: "state=exited exit_code=143",
        meta:   <<~META,
          started_at_epoch=1786701600
          pid=4242
          finished_at=2026-08-14T10:00:30Z
          finished_at_epoch=1786701630
          reason=signaled
          signal=TERM
          exit_code=143
          checked_at_epoch=1786701900
        META
        command: "make check_all",
        log:     "compiling\n"
      )

      status = Open3.stub(:popen3, popen3_stub(out: out)) do
        Coder::SshRunner.new(@integration).job_status(workspace_name: "ws-1", job_id: "j1")
      end

      assert_equal "signaled", status[:reason]
      assert_equal "TERM", status[:signal]
      assert_equal 143, status[:exit_code]
      assert_equal 30, status[:elapsed_seconds]
      assert_match(/SIGTERM/, status[:diagnosis])
      assert_match(/cancellation|outside kill/, status[:diagnosis])
      assert_nil status[:child_signal], "a forwarded signal that matched needs no second field"
      assert_nil status[:possible_causes], "a trapped signal is conclusive — it must not read as ambiguous"
    end

    # INT and QUIT cannot reach a command a non-interactive shell started in the
    # background (POSIX has the shell ignore them there), so the wrapper follows
    # with TERM. The poll must say so instead of implying the command handled
    # the signal the wrapper was sent.
    test "job status reports the signal the command was really delivered when it differs" do
      out = job_status_output(
        header: "state=exited exit_code=130",
        meta:   <<~META,
          started_at_epoch=1786701600
          pid=4242
          child_signal=TERM
          finished_at=2026-08-14T10:00:30Z
          finished_at_epoch=1786701630
          reason=signaled
          signal=INT
          exit_code=130
          checked_at_epoch=1786701900
        META
        command: "make check_all",
        log:     "compiling\n"
      )

      status = Open3.stub(:popen3, popen3_stub(out: out)) do
        Coder::SshRunner.new(@integration).job_status(workspace_name: "ws-1", job_id: "j1")
      end

      assert_equal "signaled", status[:reason]
      assert_equal "INT", status[:signal]
      assert_equal "TERM", status[:child_signal]
      assert_match(/SIGINT/, status[:diagnosis])
      assert_match(/delivered to the command as SIGTERM/, status[:diagnosis])
    end

    # The case that used to lose everything: the wrapper is SIGKILLed, so no trap
    # runs and no exit file is written. The job must still be datable and
    # attributable — from the last heartbeat, not from file mtimes recovered by
    # hand.
    test "job status dates and explains a job killed before it could write its exit code" do
      out = job_status_output(
        header: "state=died exit_code=",
        meta:   <<~META,
          job_id=j1
          workspace=ws-1
          started_at=2026-08-14T10:00:00Z
          started_at_epoch=1786701600
          heartbeat_interval_seconds=10
          pid=777
          pgid=777
          checked_at=2026-08-14T10:04:20Z
          checked_at_epoch=1786701860
          heartbeat_at=2026-08-14T10:03:20Z
          heartbeat_at_epoch=1786701800
          log_bytes=128
          log_modified_at_epoch=1786701795
        META
        command: "make check_all",
        log:     "running tests\n"
      )

      status = Open3.stub(:popen3, popen3_stub(out: out)) do
        Coder::SshRunner.new(@integration).job_status(workspace_name: "ws-1", job_id: "j1")
      end

      assert_equal "died", status[:state]
      assert_nil status[:exit_code]
      assert_equal "runner_vanished", status[:reason]
      assert_equal "2026-08-14T10:03:20Z", status[:finished_at]
      assert status[:finished_at_estimated], "a heartbeat-derived end time must be marked as an estimate"
      assert_equal 200, status[:elapsed_seconds]
      assert_equal 60, status[:heartbeat_age_seconds]
      assert_equal "2026-08-14T10:03:20Z", status[:last_heartbeat_at]
      assert_equal 777, status[:pid]
      assert_equal "make check_all", status[:command]
      assert_equal "running tests\n", status[:tail]
      assert_match(/pid 777/, status[:diagnosis])
      assert_match(/never wrote an exit code/, status[:diagnosis])
    end

    # A hard `kill -9` on the job's process group and a workspace that rebooted
    # leave byte-identical evidence: no exit file, a dead pid, a stale
    # heartbeat. The poll must not resolve that to one cause — an operator sent
    # after a phantom infrastructure failure is worse off than one told the
    # state is ambiguous.
    test "job status reports a vanished runner as indeterminate, naming both causes" do
      out = job_status_output(
        header: "state=died exit_code=",
        meta:   <<~META,
          started_at=2026-08-14T10:00:00Z
          started_at_epoch=1786701600
          pid=777
          pgid=777
          checked_at_epoch=1786701860
          heartbeat_at=2026-08-14T10:03:20Z
          heartbeat_at_epoch=1786701800
        META
        command: "make check_all",
        log:     "running tests\n"
      )

      status = Open3.stub(:popen3, popen3_stub(out: out)) do
        Coder::SshRunner.new(@integration).job_status(workspace_name: "ws-1", job_id: "j1")
      end

      assert_equal %w[hard_cancellation infrastructure_failure], status[:possible_causes],
                   "both candidate causes must be machine-readable, not buried in prose"
      assert_match(/indeterminate/, status[:diagnosis])
      assert_match(/cancellation/, status[:diagnosis], "an explicit hard kill must be named as a candidate")
      assert_match(/infrastructure failure/, status[:diagnosis], "so must the infrastructure cause")
      assert_no_match(/^the runner .*\. An infrastructure failure/, status[:diagnosis],
                      "the diagnosis must not assert a single cause")
      assert_match(/pgid 777|process group/, status[:diagnosis],
                   "the reader needs to know a process-group kill produces this too")
    end

    test "job status still explains a job whose wrapper predates lifecycle metadata" do
      out = "aixle_job state=exited exit_code=2\n---aixle_job_log---\n2 failures\n"

      status = Open3.stub(:popen3, popen3_stub(out: out)) do
        Coder::SshRunner.new(@integration).job_status(workspace_name: "ws-1", job_id: "old")
      end

      assert_equal "exited", status[:state]
      assert_equal 2, status[:exit_code]
      assert_equal "command_failed", status[:reason], "the exit code alone still classifies an old job"
      assert_equal "2 failures\n", status[:tail]
      assert_nil status[:started_at]
      assert_nil status[:elapsed_seconds]
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

    # ---------- the job wrapper, run for real ----------
    #
    # Half of this feature is shell that runs on the workspace, and a canned
    # `job_status` payload cannot tell whether the wrapper actually produces it.
    # These three exercise the generated scripts through a local shell (job files
    # in a tmpdir via AIXLE_JOB_DIR) — the same launch → poll cycle a session
    # runs, with `coder ssh` swapped for `sh -c`.

    test "a detached job that succeeds records its exit code, reason and timing" do
      in_local_shell_workspace do |runner|
        runner.exec_detached(workspace_name: "ws-1", command: "printf 'all good\\n'", job_id: "wrapok")
        status = poll_until_finished(runner, "wrapok")

        assert_equal "exited", status[:state]
        assert_equal 0, status[:exit_code]
        assert_equal "completed", status[:reason]
        assert_equal "ws-1", status[:workspace]
        assert_equal "printf 'all good\\n'", status[:command]
        assert_operator status[:pid].to_i, :>, 0
        assert_match(/\A\d{4}-\d{2}-\d{2}T/, status[:started_at])
        assert_match(/\A\d{4}-\d{2}-\d{2}T/, status[:finished_at])
        assert_operator status[:elapsed_seconds], :>=, 0
        assert_nil status[:finished_at_estimated]
        assert_equal "all good\n", status[:tail]
      end
    end

    test "a detached job that fails reports the command's own non-zero exit" do
      in_local_shell_workspace do |runner|
        runner.exec_detached(
          workspace_name: "ws-1", command: "printf 'boom\\n' >&2; exit 3", job_id: "wrapfail"
        )
        status = poll_until_finished(runner, "wrapfail")

        assert_equal "exited", status[:state]
        assert_equal 3, status[:exit_code]
        assert_equal "command_failed", status[:reason]
        assert_match(/exited 3/, status[:diagnosis])
        assert_match(/boom/, status[:tail], "stderr must still land in the job log")
      end
    end

    # Termination before the normal exit-file write: the wrapper is signalled
    # while the command is running, which used to leave the job with no exit
    # code, no end time and no reason.
    test "a detached job terminated mid-run records the signal instead of vanishing" do
      in_local_shell_workspace do |runner|
        runner.exec_detached(workspace_name: "ws-1", command: signal_reporting_command, job_id: "wrapkill")
        pid = poll_for_pid(runner, "wrapkill")

        Process.kill("TERM", pid)
        status = poll_until_finished(runner, "wrapkill")

        assert_equal "exited", status[:state]
        assert_equal 143, status[:exit_code]
        assert_equal "signaled", status[:reason]
        assert_equal "TERM", status[:signal]
        assert_not_nil status[:finished_at], "an interrupted job must still be dated"
        assert_operator status[:elapsed_seconds], :>=, 0
        assert_match(/SIGTERM/, status[:diagnosis])
        assert_match(/command received TERM/, wait_for_tail(runner, "wrapkill", /command received/),
                     "the command must be sent the signal the wrapper recorded")
      end
    end

    # A non-TERM trap, run for real: the command must receive the same signal
    # the wrapper did, or the recorded `signal` describes something that never
    # happened. HUP is the interesting one — unlike INT/QUIT a background child
    # can actually receive it, so nothing may substitute TERM for it.
    test "a detached job terminated with HUP forwards HUP, not TERM" do
      in_local_shell_workspace do |runner|
        runner.exec_detached(workspace_name: "ws-1", command: signal_reporting_command, job_id: "wraphup")
        pid = poll_for_pid(runner, "wraphup")

        Process.kill("HUP", pid)
        status = poll_until_finished(runner, "wraphup")

        assert_equal "exited", status[:state]
        assert_equal 129, status[:exit_code]
        assert_equal "signaled", status[:reason]
        assert_equal "HUP", status[:signal]
        assert_nil status[:child_signal], "HUP reaches the command; nothing should have been substituted"
        assert_match(/SIGHUP/, status[:diagnosis])

        tail = wait_for_tail(runner, "wraphup", /command received/)
        assert_match(/command received HUP/, tail, "the command must be sent the signal the wrapper recorded")
        assert_no_match(/command received TERM/, tail, "TERM must not be substituted for a forwarded HUP")
      end
    end

    # Why the INT/QUIT branch of the trap exists at all, pinned to the POSIX
    # behaviour it is written for: a non-interactive shell sets INT and QUIT to
    # ignore in a command it starts in the background, and a shell cannot
    # re-trap a signal inherited as ignored. The wrapper is launched in the
    # background, so an INT aimed at a detached job reaches nothing and the job
    # keeps running — a cancellation must use TERM. The command is started in
    # the background too, which is why an INT the wrapper *can* receive is
    # forwarded as TERM and recorded as `child_signal` (covered above).
    test "INT does not reach a detached wrapper, so the job keeps running" do
      in_local_shell_workspace do |runner|
        runner.exec_detached(workspace_name: "ws-1", command: signal_reporting_command, job_id: "wrapint")
        pid = poll_for_pid(runner, "wrapint")

        Process.kill("INT", pid)
        sleep 0.5

        status = runner.job_status(workspace_name: "ws-1", job_id: "wrapint")
        assert_equal "running", status[:state], "a background wrapper cannot be interrupted by INT (POSIX)"
        assert_empty status[:tail].to_s.strip, "and the command must not have seen it either"

        # Leave nothing behind: TERM is the signal that does reach it.
        Process.kill("TERM", pid)
        assert_equal "TERM", poll_until_finished(runner, "wrapint")[:signal]
      end
    end

    private

    # A command that names the signal it was sent in its own log, so a test can
    # tell what the wrapper really delivered rather than trusting the metadata
    # it wrote. Sleeps in short slices because a POSIX shell runs a trap only
    # once the foreground command returns.
    def signal_reporting_command
      <<~CMD
        trap 'printf "command received TERM\\n"; exit 143' TERM
        trap 'printf "command received HUP\\n"; exit 129' HUP
        trap 'printf "command received INT\\n"; exit 130' INT
        i=0
        while [ "$i" -lt 300 ]; do sleep 0.1; i=$((i + 1)); done
      CMD
    end

    # The wrapper records its own end and exits without waiting for the command,
    # so the command's last line can land in the log just after the poll reports
    # the job finished.
    def wait_for_tail(runner, job_id, pattern, timeout: 10)
      poll(timeout: timeout, waiting_for: "job #{job_id} log to match #{pattern.inspect}") do
        tail = runner.job_status(workspace_name: "ws-1", job_id: job_id)[:tail].to_s
        tail if tail.match?(pattern)
      end
    end

    # Assembles a `job_status` remote payload the way the status script does:
    # header, metadata, launch command, log tail.
    def job_status_output(header:, meta:, command:, log:)
      [
        "aixle_job #{header}\n",
        "---aixle_job_meta---\n", meta,
        "---aixle_job_cmd---\n", "#{command}\n\n",
        "---aixle_job_log---\n", log
      ].join
    end

    # Runs the remote command through the local shell instead of `coder ssh`.
    # `Open3.popen3` is captured before it is stubbed, so the stub can still
    # reach the real implementation.
    def in_local_shell_workspace
      real_popen3 = Open3.method(:popen3)
      job_dir     = Dir.mktmpdir("aixle-jobs")
      local_shell = lambda { |env, *argv, **opts, &blk|
        real_popen3.call(env.merge("AIXLE_JOB_DIR" => job_dir), "sh", "-c", argv.last, **opts, &blk)
      }

      Open3.stub(:popen3, local_shell) do
        yield Coder::SshRunner.new(@integration)
      end
    ensure
      FileUtils.remove_entry(job_dir) if job_dir && File.directory?(job_dir)
    end

    def poll_until_finished(runner, job_id, timeout: 15)
      poll(timeout: timeout, waiting_for: "job #{job_id} to finish") do
        status = runner.job_status(workspace_name: "ws-1", job_id: job_id)
        status if status[:state] != "running"
      end
    end

    def poll_for_pid(runner, job_id, timeout: 15)
      poll(timeout: timeout, waiting_for: "job #{job_id} to report its pid") do
        runner.job_status(workspace_name: "ws-1", job_id: job_id)[:pid]
      end
    end

    def poll(timeout:, waiting_for:)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      loop do
        result = yield
        return result if result
        flunk "timed out after #{timeout}s waiting for #{waiting_for}" if
          Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        sleep 0.05
      end
    end

    def with_settings_ceiling(seconds)
      original = Settings.coder.ssh_exec_ceiling_seconds
      Settings.coder.ssh_exec_ceiling_seconds = seconds
      yield
    ensure
      Settings.coder.ssh_exec_ceiling_seconds = original
    end
  end
end
