# frozen_string_literal: true

require "openssl"
require "socket"
require "uri"
require "websocket"

module ContainerRuntime
  # Client end of a Kubernetes exec websocket. Callbacks are registered in the
  # block #connect yields, before the socket opens, and run on the reader thread.
  #
  # Not websocket-client-simple: it reads the socket one byte at a time and runs
  # the frame parser on every byte — about 12 Ruby allocations per byte, all of
  # it holding the GVL. Copying a 1 MB file out of a pod cost 12.6M allocations
  # and 13 s, and every other request on the same Puma process stalled behind it
  # (PALAD-AI-RAILS-45).
  class ExecWebsocket
    READ_CHUNK_BYTES = 64 * 1024
    HEADER_END = "\r\n\r\n"
    READER_JOIN_SECONDS = 1

    # Without this the websocket gem's parsers swallow a refused upgrade or a
    # malformed frame into a symbol on the parser instead of raising it.
    ::WebSocket.should_raise = true

    def self.connect(url, headers: {})
      client = new
      yield client if block_given?
      client.connect(url, headers: headers)
      client
    end

    attr_reader :handshake

    def initialize
      @listeners = Hash.new { |listeners, event| listeners[event] = [] }
      @state_lock = Mutex.new
      @write_lock = Mutex.new
      @closed = false
      @upgraded = false
    end

    def on(event, &block)
      @listeners[event] << block
    end

    def connect(url, headers: {})
      uri = URI.parse(url)
      @handshake = ::WebSocket::Handshake::Client.new(url: url, headers: headers)
      @socket = open_socket(uri)
      @socket.write(@handshake.to_s)
      @reader = Thread.new { read_loop }
    rescue StandardError
      @socket&.close
      raise
    end

    # Binary by default: stdin is arbitrary bytes, and a text frame must be
    # valid UTF-8.
    def send(data, type: :binary)
      return if !@upgraded || @closed

      write_frame(data, type)
    end

    def closed?
      @closed
    end

    def close
      @state_lock.synchronize do
        return if @closed

        @closed = true
      end

      write_frame("", :close) if @upgraded
      @socket&.close
      emit(:close)
      stop_reader
    end

    private

    def open_socket(uri)
      tcp = TCPSocket.new(uri.host, uri.port)
      return tcp unless %w[https wss].include?(uri.scheme)

      context = OpenSSL::SSL::SSLContext.new
      context.cert_store = OpenSSL::X509::Store.new.tap(&:set_default_paths)
      tls = OpenSSL::SSL::SSLSocket.new(tcp, context)
      tls.sync_close = true
      tls.hostname = uri.host
      tls.connect
      tls
    end

    def read_loop
      buffer = +"".b

      until @closed
        chunk = @socket.readpartial(READ_CHUNK_BYTES)
        if @upgraded
          receive_frames(chunk)
        else
          buffer = receive_upgrade(buffer << chunk)
        end
      end
    rescue EOFError
      fail_with(EOFError.new("the API server dropped the exec connection without a close frame"))
    rescue StandardError => e
      fail_with(e)
    end

    # The response headers and the first frames can arrive in the same read,
    # so the upgrade is split off at the blank line by hand: the gem's own
    # `leftovers` strips whitespace and would eat binary frame bytes.
    def receive_upgrade(buffer)
      header_end = buffer.index(HEADER_END)
      return buffer unless header_end

      split = header_end + HEADER_END.bytesize
      @handshake << buffer.byteslice(0, split)
      @frames = ::WebSocket::Frame::Incoming::Client.new(version: @handshake.version)
      @upgraded = true
      emit(:open)

      rest = buffer.byteslice(split, buffer.bytesize - split)
      receive_frames(rest) unless rest.empty?
      nil
    end

    def receive_frames(chunk)
      @frames << chunk

      while (frame = @frames.next)
        case frame.type
        when :text, :binary then emit(:message, frame)
        when :ping then write_frame(frame.data, :pong)
        when :close then return close
        end
      end
    end

    def write_frame(data, type)
      frame = ::WebSocket::Frame::Outgoing::Client.new(version: @handshake.version, data: data, type: type)
      @write_lock.synchronize { @socket.write(frame.to_s) }
    rescue IOError, SystemCallError, OpenSSL::SSL::SSLError
      close unless type == :close
    end

    def fail_with(error)
      emit(:error, error) unless @closed
    end

    def emit(event, *args)
      @listeners[event].each { |listener| listener.call(*args) }
    end

    # #close also runs from the reader thread's own callbacks (a remote close
    # frame, the :error listener), where the reader simply stops at the top of
    # its loop. From any other thread the reader may be parked in a callback
    # waiting on the caller's lock, so it gets a moment and is then killed.
    def stop_reader
      return if @reader.nil? || Thread.current.equal?(@reader)
      return if @reader.join(READER_JOIN_SECONDS)

      @reader.kill
    end
  end
end
