# frozen_string_literal: true

require "open3"
require "test_helper"

module Sessions
  class SnapshotTest < ActiveSupport::TestCase
    setup do
      @user = create(:user, :with_company)
      @project = create(:project, owner: @user, company: @user.companies.first)
      @runtime = stub_container_runtime
      @session = create(:terminal_session, session_type: "workflow_step", state: "ready", user: @user,
                                           project: @project, container_id: "ctr-1", started_at: 1.hour.ago)
    end

    teardown do
      cleanup_runtime_overrides
    end

    def read(parts)
      Snapshot.read(@session, parts: parts, runtime: @runtime)
    end

    test "reads every requested part with one exec" do
      @runtime.set_terminal_pane("● Working\n> \n", last_output_at: 3.minutes.ago)
      @runtime.set_terminal_clients([ [ false, 2.minutes.ago ] ])

      snapshot = read(%i[scrollback log_mtime clients])

      assert_equal 1, @runtime.execs.size
      assert_equal "● Working\n> \n", snapshot.scrollback
      assert_in_delta 3.minutes.ago, snapshot.last_output_at, 1.second
      assert snapshot.clients.input_within?(10.minutes)
      refute snapshot.clients.input_within?(1.minute)
    end

    test "builds the exec from the parts asked for only" do
      read(%i[scrollback])

      command = @runtime.execs.last.join(" ")
      assert_includes command, "capture-pane -t agent -p -S -#{Snapshot::Parts::SCROLLBACK_LINES}"
      refute_includes command, "list-clients"
      refute_includes command, Snapshot::Parts::TERMINAL_LOG_PATH
    end

    test "a part that fails leaves the others readable" do
      @runtime.set_terminal_pane("> \n", last_output_at: 3.minutes.ago)
      @runtime.fail_exec("list-clients")

      snapshot = read(%i[scrollback log_mtime clients])

      assert_equal "> \n", snapshot.scrollback
      assert_nil snapshot.clients
      assert snapshot.quiet_for?(1.minute)
    end

    # As Sessions::AuthPause#quiet? did: a container whose tmux is gone still has a log.
    test "the log's mtime counts only from a read that also captured the pane" do
      @runtime.set_terminal_pane("> \n", last_output_at: 3.minutes.ago)
      @runtime.fail_exec("capture-pane")

      snapshot = read(%i[scrollback log_mtime])

      assert_nil snapshot.scrollback
      assert_nil snapshot.last_output_at
      refute snapshot.quiet_for?(1.minute), "an unknown pane is not a quiet one"
    end

    test "the current screen is the pane's last nonblank lines, right-trimmed" do
      pane = "#{(1..50).map { |i| "line #{i}   " }.join("\n")}\n\n\n"
      @runtime.set_terminal_pane(pane)

      snapshot = read(%i[scrollback])

      assert_equal Snapshot::SCREEN_LINES, snapshot.screen.size
      assert_equal "line 50", snapshot.screen.last
      assert_equal ScreenDigest.of(pane), snapshot.screen_digest
    end

    # The pane is the agent's own work, and an agent can print anything, this file included.
    test "a pane that prints a marker-looking line is read whole" do
      pane = "#{Snapshot::Command::MARKER_PREFIX}0000__ end 0\n> \n"
      @runtime.set_terminal_pane(pane)

      assert_equal pane, read(%i[scrollback]).scrollback
    end

    test "a container that is not there reads as nothing, without an exec" do
      @session.update_columns(container_id: nil)

      snapshot = read(%i[scrollback log_mtime])

      assert_nil snapshot.scrollback
      assert_empty @runtime.execs
    end

    test "a container that is gone is the caller's to skip" do
      @runtime.unreachable_on_exec(Snapshot::Command::MARKER_PREFIX)

      assert_raises(ContainerRuntime::ContainerUnreachableError) { read(%i[scrollback]) }
    end

    test "an exec that blows up reads as nothing" do
      @runtime.raise_on_exec(Snapshot::Command::MARKER_PREFIX)
      Rails.logger.stubs(:warn)

      assert_nil read(%i[scrollback]).scrollback
    end

    test "an unknown part is refused" do
      assert_raises(ArgumentError) { read(%i[scrollback something_else]) }
    end

    test "parses the shell's own output" do
      command = Snapshot::Command.new(%i[scrollback log_mtime clients], nonce: "abc")
      stdout = "__aixle_snapshot_abc__ scrollback\none\ntwo\n\n__aixle_snapshot_abc__ end 0\n" \
               "__aixle_snapshot_abc__ log_mtime\n\n__aixle_snapshot_abc__ end 1\n" \
               "__aixle_snapshot_abc__ clients\n1700000000\n0 1699999990\n\n__aixle_snapshot_abc__ end 0\n"

      parsed = command.parse(stdout)

      assert_equal "one\ntwo\n", parsed[:scrollback]
      refute parsed.key?(:log_mtime), "a fragment that exited non-zero was not read"
      assert_equal "1700000000\n0 1699999990\n", parsed[:clients]
    end

    # The script itself, through a real /bin/sh, against stub `tmux` and `stat` on PATH: the
    # footer on its own line after output with no final newline, each fragment's own status,
    # `date && tmux list-clients` failing as one unit, and the client format reaching tmux
    # as a literal.
    test "the script read through a real shell parses into its parts and leaves out a failed one" do
      Dir.mktmpdir do |bin|
        stub_tool(bin, "tmux", <<~'SH')
          case "$1" in
            capture-pane) printf '● Working\n> ' ;;
            list-clients)
              [ "$5" = '#{client_readonly} #{client_activity}' ] || exit 3
              echo '0 1699999990' ;;
            *) exit 2 ;;
          esac
        SH
        stub_tool(bin, "stat", "echo 'stat: cannot stat' >&2; exit 1")
        command = Snapshot::Command.new(%i[scrollback log_mtime clients])

        stdout, status = Open3.capture2({ "PATH" => "#{bin}:#{ENV.fetch('PATH')}" }, *command.argv)
        parsed = command.parse(stdout)

        assert status.success?, stdout
        assert_equal "● Working\n> ", parsed[:scrollback]
        refute parsed.key?(:log_mtime), "the fragment whose stat exited non-zero was not read"
        clock, client = parsed[:clients].split("\n")
        assert_match(/\A\d+\z/, clock, "the container's clock comes first")
        assert_equal "0 1699999990", client
        assert_equal [ [ false, 1_699_999_990 ] ], Snapshot::Parts.fetch(:clients).parse.call(parsed[:clients]).rows
      end
    end

    def stub_tool(bin, name, body)
      path = File.join(bin, name)
      File.write(path, "#!/bin/sh\n#{body}\n")
      File.chmod(0o755, path)
    end
  end
end
