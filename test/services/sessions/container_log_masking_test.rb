# frozen_string_literal: true

require "test_helper"
require "open3"

module Sessions
  # The container's log filters run inside agent images, so they are exercised as the
  # scripts they are — real python3 and node — against recordings of a real session.
  class ContainerLogMaskingTest < ActiveSupport::TestCase
    include SecretLeakAssertions

    LOGGER = Rails.root.join("docker/base/logger")

    setup do
      @dir = Dir.mktmpdir("container-masking")
      @list = File.join(@dir, "redact.list")
      File.write(@list, "#{Base64.strict_encode64(RECORDED_SECRET)}\n")
    end

    teardown { FileUtils.rm_rf(@dir) }

    test "the pane filter masks every copy of the secret in the recorded session" do
      raw = recording("claude_code_2.1.310_terminal.log")
      assert_operator recovered(raw), :>=, RECORDED_SECRET.length, "the recording no longer holds the secret"

      masked = execute("python3", LOGGER.join("redact-stream.py").to_s, stdin: raw)

      assert_no_secret masked
      assert_equal raw.bytesize, masked.bytesize, "masking moved what the terminal paints"
    end

    # A pipe hands the filter whatever the PTY wrote, cut anywhere: inside an escape
    # sequence, between the two rows of a wrapped value, one byte at a time.
    test "the pane filter masks the recorded session however its output is chunked" do
      script = <<~'PY'
        import base64, random, sys
        sys.path.insert(0, sys.argv[1])
        import aixle_redact
        raw = sys.stdin.buffer.read()
        for seed in range(12):
            rng = random.Random(seed)
            stream, out, i = aixle_redact.TerminalStream(), bytearray(), 0
            while i < len(raw):
                size = rng.choice([1, 2, 3, 7, 64, 4096])
                out += stream.feed(raw[i:i + size])
                i += size
            out += stream.flush()
            print(base64.b64encode(bytes(out)).decode())
      PY

      outputs = execute("python3", "-c", script, LOGGER.to_s, stdin: recording("claude_code_2.1.310_terminal.log")).split

      assert_equal 12, outputs.size
      outputs.each { |encoded| assert_no_secret Base64.decode64(encoded) }
    end

    test "the proxy log masks a value the model streamed back a few characters per event" do
      stream = recording("anthropic_messages_stream.sse")
      assert_not_includes stream, RECORDED_SECRET, "the recording is meant to hold the secret only in pieces"
      assert_operator recovered(streamed_text(stream)), :>=, RECORDED_SECRET.length

      script = "import sys; sys.path.insert(0, sys.argv[1]); import aixle_redact; " \
               "sys.stdout.write(aixle_redact.mask_body(sys.stdin.read()))"
      masked = execute("python3", "-c", script, LOGGER.to_s, stdin: stream)

      assert_no_secret streamed_text(masked)
      assert_no_secret masked
      assert_equal stream.lines.grep(/\Adata:/).size, masked.lines.grep(/\Adata:/).size
    end

    test "a masked transcript keeps every line and none of the secret" do
      source = File.join(@dir, "transcript.jsonl")
      copy = File.join(@dir, "masked.jsonl")
      File.binwrite(source, recording("claude_code_2.1.310_transcript.jsonl"))

      written = execute("python3", LOGGER.join("aixle_redact.py").to_s, "file", "jsonl", source, copy)

      masked = File.read(copy)
      assert_equal masked.bytesize, written.to_i
      assert_no_secret masked
      assert_equal File.read(source).lines.size, masked.lines.size
      masked.each_line { |line| JSON.parse(line) }
    end

    test "a binary body keeps its length with the secret's bytes masked" do
      body = "\x0a\x2bkey:#{RECORDED_SECRET[0, 20]}\x12\x05#{RECORDED_SECRET[20..]}\x18\x01".b
      script = "import sys; sys.path.insert(0, sys.argv[1]); import aixle_redact; " \
               "sys.stdout.buffer.write(aixle_redact.mask_binary(sys.stdin.buffer.read()))"

      masked = execute("python3", "-c", script, LOGGER.to_s, stdin: body)

      assert_equal body.bytesize, masked.bytesize
      assert_no_secret masked
      assert_equal "\x0a\x2bkey:".b, masked.byteslice(0, 6)
    end

    test "the masker finds a short secret whose closing punctuation was escaped" do
      File.write(@list, "#{Base64.strict_encode64('Summer2024!')}\n")
      script = "import sys; sys.path.insert(0, sys.argv[1]); import aixle_redact; " \
               "sys.stdout.write(aixle_redact.mask_text(sys.stdin.read()))"

      masked = execute("python3", "-c", script, LOGGER.to_s, stdin: %(curl -u "qa:Summer2024\\!" https://x.test))

      assert_not_includes masked, "Summer2024"
      assert_includes masked, "curl -u \"qa:"
    end

    test "the HTTP/2 logger masks a value split across a line in any field" do
      entry = { path: "/v1/run?key=pxk_l\e[39m\r\n  ive_7Hq2ZtR9mWb4Nc8VxL1aPe6Ks3Dy5Fg0Ju", host: "api.test" }
      script = "const r = require(process.argv[1]); process.stdout.write(JSON.stringify(r.redact(#{entry.to_json})))"

      # Copied out of the repository, whose package.json makes every .js file an ES module;
      # in the image it sits in /opt/mitm, where it is plain CommonJS.
      module_path = File.join(@dir, "aixle-redact.js")
      FileUtils.cp(LOGGER.join("aixle-redact.js"), module_path)
      masked = JSON.parse(execute("node", "-e", script, module_path))

      assert_no_secret masked["path"]
      assert_includes masked["path"], "/v1/run?key="
      assert_equal "api.test", masked["host"]
    end

    private

    def execute(*command, stdin: nil)
      out, err, status = Open3.capture3({ "AIXLE_REDACT_LIST" => @list }, *command, stdin_data: stdin.to_s, binmode: true)
      assert status.success?, "#{command.first} failed: #{err}"
      out
    end

    # Each content block's streamed deltas joined, as a reader replaying the stream would.
    def streamed_text(body)
      blocks = Hash.new { |h, k| h[k] = +"" }
      body.each_line do |line|
        next unless line.start_with?("data:")

        event = JSON.parse(line.delete_prefix("data:"))
        delta = event["delta"]
        next unless delta.is_a?(Hash)

        blocks[event["index"]] << delta.values_at("text", "partial_json", "thinking").compact.join
      end
      blocks.values.join("\n")
    end
  end
end
