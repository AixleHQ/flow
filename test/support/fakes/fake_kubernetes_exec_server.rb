# frozen_string_literal: true

require "openssl"
require "socket"
require "uri"
require "websocket"

# A local stand-in for the Kubernetes API server's pod exec endpoint: a real
# TCP (optionally TLS) listener that upgrades to a websocket and speaks the
# channel.k8s.io protocol, so ContainerRuntime::ExecWebsocket and
# KubernetesRuntime#exec run unmodified against it — nothing vendor-owned is
# stubbed (docs/testing.md R2).
#
# The exchange mirrors what a v1.34 API server was observed to send: the 101,
# an empty stdout frame, output in frames of at most 32 KiB, the Status on
# channel 3, a close frame with code 1000, then the TCP close.
#
# The pod is a block: it receives the exec's command and stdin and returns
# [stdout, stderr, exit_code]. Every exec is recorded in #execs, and anything
# the client sent that the server could not parse lands in #errors.
class FakeKubernetesExecServer
  FRAME_BYTES = 32 * 1024
  PROTOCOLS = %w[v4.channel.k8s.io v5.channel.k8s.io].freeze

  Exec = Struct.new(:command, :stdin, :protocol, :client_frame_types, keyword_init: true)

  attr_reader :execs, :errors

  # refuse:   an HTTP status line to answer the upgrade with instead of 101
  # coalesce: send the 101 and every frame in one write, so the first frames
  #           land in the same read as the upgrade response
  # drip:     write the response a few bytes at a time, so frames straddle reads
  # ping:     send a ping before the output and expect a pong back
  # ending:   :close_frame as the API server does; :eof_after_status drops the
  #           TCP connection after the Status without a close frame;
  #           :eof_before_status drops it right after the output
  def initialize(tls: false, refuse: nil, coalesce: false, drip: false, ping: false, ending: :close_frame, &pod)
    @tls = tls
    @refuse = refuse
    @coalesce = coalesce
    @drip = drip
    @ping = ping
    @ending = ending
    @pod = pod || ->(_command, _stdin) { [ "", "", 0 ] }
    @execs = []
    @errors = []
  end

  def self.tls_context
    @tls_context ||= begin
      key = OpenSSL::PKey::RSA.new(2048)
      cert = OpenSSL::X509::Certificate.new
      cert.version = 2
      cert.serial = 1
      cert.subject = cert.issuer = OpenSSL::X509::Name.parse("/CN=127.0.0.1")
      cert.public_key = key.public_key
      cert.not_before = Time.now - 60
      cert.not_after = Time.now + 3600
      cert.sign(key, OpenSSL::Digest.new("SHA256"))

      context = OpenSSL::SSL::SSLContext.new
      context.cert = cert
      context.key = key
      context
    end
  end

  def start
    @listener = TCPServer.new("127.0.0.1", 0)
    @acceptor = Thread.new { accept_loop }
    self
  end

  def stop
    @acceptor&.kill
    @listener&.close
  end

  def base_url
    "#{@tls ? 'https' : 'http'}://127.0.0.1:#{@listener.addr[1]}"
  end

  # An exec URL shaped like the one KubernetesRuntime builds.
  def exec_url(command:, stdin: false)
    query = [ "stdin=#{stdin}", "stdout=true", "stderr=true", "tty=false", "container=main" ] +
            command.map { |part| "command=#{URI.encode_www_form_component(part)}" }
    "#{base_url}/api/v1/namespaces/default/pods/pod/exec?#{query.join('&')}"
  end

  private

  def accept_loop
    loop do
      client = @listener.accept
      Thread.new(client) { |socket| serve(wrap(socket)) }
    end
  rescue IOError, SystemCallError
    nil # the listener was closed
  end

  def wrap(socket)
    return socket unless @tls

    tls = OpenSSL::SSL::SSLSocket.new(socket, self.class.tls_context)
    tls.sync_close = true
    tls.accept
    tls
  end

  def serve(socket)
    request = read_request(socket)
    return refuse_upgrade(socket) if @refuse

    handshake = WebSocket::Handshake::Server.new(protocols: PROTOCOLS)
    handshake << request
    exec = Exec.new(command: command_of(handshake), protocol: handshake.headers["sec-websocket-protocol"],
                    client_frame_types: [])
    @execs << exec

    incoming = WebSocket::Frame::Incoming::Server.new(version: handshake.version)
    stdin_requested = query_of(handshake)["stdin"] == "true"
    upgrade = handshake.to_s
    if !@coalesce || stdin_requested || @ping
      socket.write(upgrade)
      upgrade = nil
    end

    if @ping
      socket.write(frame(:ping, "are you there"))
      exec.client_frame_types << next_frame(socket, incoming)&.type
    end
    exec.stdin = stdin_requested ? read_stdin(socket, incoming) : nil

    stdout, stderr, exit_code = @pod.call(exec.command, exec.stdin)
    respond(socket, upgrade, stdout, stderr, exit_code)
  rescue IOError, SystemCallError, OpenSSL::SSL::SSLError
    nil # the client hung up
  rescue WebSocket::Error => e
    @errors << e
  ensure
    socket.close unless socket.closed?
  end

  def respond(socket, upgrade, stdout, stderr, exit_code)
    bytes = +"".b
    bytes << upgrade if upgrade
    bytes << frame(:binary, channel(1, ""))
    each_frame_of(stdout) { |chunk| bytes << frame(:binary, channel(1, chunk)) }
    each_frame_of(stderr) { |chunk| bytes << frame(:binary, channel(2, chunk)) }
    bytes << frame(:binary, channel(3, status_json(exit_code))) unless @ending == :eof_before_status
    bytes << frame(:close, "") if @ending == :close_frame

    if @drip
      bytes.each_char.each_slice(3) { |piece| socket.write(piece.join) }
    else
      socket.write(bytes)
    end
  end

  def read_request(socket)
    request = +""
    request << socket.readpartial(4096) until request.include?("\r\n\r\n")
    request
  end

  def refuse_upgrade(socket)
    body = { kind: "Status", status: "Failure", reason: "NotFound", code: @refuse.to_i }.to_json
    socket.write("HTTP/1.1 #{@refuse}\r\nContent-Type: application/json\r\n" \
                 "Content-Length: #{body.bytesize}\r\n\r\n#{body}")
    socket.read # hold the connection; the client decides when it ends
  end

  # v5 ends stdin with a frame on channel 255 naming stream 0; nothing else
  # in this protocol tells the server the input is complete.
  def read_stdin(socket, incoming)
    stdin = +"".b
    while (message = next_frame(socket, incoming))
      data = message.data.to_s.b
      break if data == [ 255, 0 ].pack("C*")

      stdin << data.byteslice(1, data.bytesize - 1) if data.getbyte(0).zero?
    end
    stdin
  end

  def next_frame(socket, incoming)
    loop do
      message = incoming.next
      return message if message

      incoming << socket.readpartial(4096)
    end
  rescue EOFError
    nil
  end

  def each_frame_of(output)
    data = output.to_s.b
    (0...data.bytesize).step(FRAME_BYTES) { |offset| yield data.byteslice(offset, FRAME_BYTES) }
  end

  def frame(type, data)
    WebSocket::Frame::Outgoing::Server.new(version: 13, type: type, data: data).to_s
  end

  def channel(number, data)
    [ number ].pack("C") + data.b
  end

  def status_json(exit_code)
    return { metadata: {}, status: "Success" }.to_json if exit_code.zero?

    { metadata: {}, status: "Failure",
      message: "command terminated with non-zero exit code: #{exit_code}", reason: "NonZeroExitCode",
      details: { causes: [ { reason: "ExitCode", message: exit_code.to_s } ] } }.to_json
  end

  def query_of(handshake)
    URI.decode_www_form(handshake.query.to_s).to_h
  end

  def command_of(handshake)
    URI.decode_www_form(handshake.query.to_s).filter_map { |key, value| value if key == "command" }
  end
end
