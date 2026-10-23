# frozen_string_literal: true

require "test_helper"

module ContainerRuntime
  class ExecWebsocketTest < ActiveSupport::TestCase
    Result = Struct.new(:client, :events, keyword_init: true) do
      def channel(number)
        messages.filter_map { |data| data.byteslice(1, data.bytesize - 1) if data.getbyte(0) == number }.join.b
      end

      def messages
        events.filter_map { |event, payload| payload.data.to_s.b if event == :message }
      end

      def count(name)
        events.count { |event, _payload| event == name }
      end

      def errors
        events.filter_map { |event, payload| payload if event == :error }
      end
    end

    teardown do
      @server&.stop
      assert_empty @server.errors if @server
    end

    test "a megabyte of binary output arrives byte for byte, starting in the same read as the upgrade" do
      output = Random.bytes(1024 * 1024)
      @server = FakeKubernetesExecServer.new(coalesce: true) { |_command, _stdin| [ output, "", 0 ] }.start

      result = run_exec(command: [ "cat", "/workspace/blob" ])

      assert_equal output, result.channel(1)
      assert_equal({ "metadata" => {}, "status" => "Success" }, JSON.parse(result.channel(3)))
      assert_equal 1, result.count(:open)
      assert_equal 1, result.count(:close)
      assert_empty result.errors
      assert result.client.closed?
    end

    test "frames split across reads are reassembled" do
      @server = FakeKubernetesExecServer.new(drip: true) { |_command, _stdin| [ "line\n" * 900, "warning\n", 2 ] }.start

      result = run_exec(command: [ "sh", "-c", "noisy" ])

      assert_equal "line\n" * 900, result.channel(1)
      assert_equal "warning\n", result.channel(2)
      assert_equal "2", JSON.parse(result.channel(3)).dig("details", "causes", 0, "message")
    end

    # The replaced client allocated ~27 objects per byte received against this
    # server (28M for this test). Reading in chunks costs a few per frame.
    test "reading a megabyte allocates per chunk, not per byte" do
      output = Random.bytes(1024 * 1024)
      @server = FakeKubernetesExecServer.new { |_command, _stdin| [ output, "", 0 ] }.start

      before = GC.stat(:total_allocated_objects)
      result = run_exec(command: [ "cat", "/workspace/blob" ])
      allocated = GC.stat(:total_allocated_objects) - before

      assert_equal output.bytesize, result.channel(1).bytesize
      assert_operator allocated, :<, 50_000
    end

    test "a ping is answered with a pong" do
      @server = FakeKubernetesExecServer.new(ping: true) { |_command, _stdin| [ "pong received\n", "", 0 ] }.start

      result = run_exec(command: [ "true" ])

      assert_equal [ :pong ], @server.execs.last.client_frame_types
      assert_equal "pong received\n", result.channel(1)
    end

    test "stdin goes out on channel 0 and is ended with a channel 255 close" do
      input = Random.bytes(200 * 1024)
      @server = FakeKubernetesExecServer.new { |_command, stdin| [ stdin, "", 0 ] }.start

      result = run_exec(command: [ "cat" ], stdin: input, protocol: "v5.channel.k8s.io")

      assert_equal input, @server.execs.last.stdin
      assert_equal input, result.channel(1)
      assert_equal "v5.channel.k8s.io", @server.execs.last.protocol
    end

    test "an https endpoint is spoken to over TLS" do
      @server = FakeKubernetesExecServer.new(tls: true) { |_command, _stdin| [ "over tls\n", "", 0 ] }.start

      result = run_exec(command: [ "true" ])

      assert_equal "over tls\n", result.channel(1)
      assert_empty result.errors
    end

    test "a refused upgrade is reported once, as the handshake error" do
      @server = FakeKubernetesExecServer.new(refuse: "404 Not Found").start

      result = run_exec(command: [ "true" ], until_event: :error)

      assert_equal 1, result.errors.size
      assert_kind_of ::WebSocket::Error::Handshake::InvalidStatusCode, result.errors.first
      assert_equal 0, result.count(:open)
    end

    test "a connection dropped without a close frame is an error, not a clean close" do
      @server = FakeKubernetesExecServer.new(ending: :eof_before_status) { |_command, _stdin| [ "partial", "", 0 ] }.start

      result = run_exec(command: [ "true" ], until_event: :error)

      assert_equal "partial", result.channel(1)
      assert_kind_of EOFError, result.errors.first
      assert_equal 0, result.count(:close)
    end

    test "closing from another thread stops the reader before the rest of the output" do
      release = Queue.new
      @server = FakeKubernetesExecServer.new do |_command, _stdin|
        release.pop
        [ "too late\n", "", 0 ]
      end.start
      events = Queue.new

      client = ExecWebsocket.connect(@server.exec_url(command: [ "sleep", "1" ]), headers: {}) do |ws|
        %i[open message error close].each { |name| ws.on(name) { |payload = nil| events << [ name, payload ] } }
      end
      assert_equal :open, events.pop(timeout: 5)&.first
      client.close
      release << true

      seen = []
      while (event = events.pop(timeout: 0.5))
        seen << event.first
      end
      assert_equal [ :close ], seen
      assert client.closed?
    end

    private

    def run_exec(command:, stdin: nil, protocol: "v4.channel.k8s.io", until_event: :close)
      events = Queue.new
      headers = { "Sec-WebSocket-Protocol" => protocol }
      url = @server.exec_url(command: command, stdin: !stdin.nil?)

      client = ExecWebsocket.connect(url, headers: headers) do |ws|
        %i[open message error close].each { |name| ws.on(name) { |payload = nil| events << [ name, payload ] } }
        ws.on(:open) { send_stdin(ws, stdin) } if stdin
      end

      seen = []
      until seen.last&.first == until_event
        event = events.pop(timeout: 10)
        flunk "no #{until_event} within 10s; saw #{seen.map(&:first)}" unless event
        seen << event
      end
      # Anything that would still follow — a second error, a late message.
      while (event = events.pop(timeout: 0.3))
        seen << event
      end
      client.close

      Result.new(client: client, events: seen)
    end

    def send_stdin(client, stdin)
      Thread.new do
        io = StringIO.new(stdin)
        while (chunk = io.read(16_384))
          client.send([ 0 ].pack("C") + chunk)
        end
        client.send([ 255, 0 ].pack("C*"))
      end
    end
  end
end
