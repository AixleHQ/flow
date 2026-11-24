# frozen_string_literal: true

require "test_helper"
require "open3"

module Agents
  # docker/base/logger/mitm_logger.py is a mitmproxy addon, run here as the python3 script
  # it is, with mitmproxy itself replaced by the few objects the addon touches. The
  # platform decides what it logs (Agents::BaseAdapter#mitm_env), so these drive it with
  # each adapter's own settings: a body a usage parser reads must survive, every other
  # body must not.
  class MitmLoggerTest < ActiveSupport::TestCase
    LOGGER = Rails.root.join("docker/base/logger/mitm_logger.py").to_s

    HARNESS = <<~PYTHON
      import importlib.util, json, sys, types

      mitmproxy = types.ModuleType("mitmproxy")
      http_mod = types.ModuleType("mitmproxy.http")
      http_mod.HTTPFlow = object
      net = types.ModuleType("mitmproxy.net")
      encoding = types.ModuleType("mitmproxy.net.encoding")
      encoding.decode = lambda raw, name: raw
      mitmproxy.http, mitmproxy.net, net.encoding = http_mod, net, encoding
      sys.modules.update({"mitmproxy": mitmproxy, "mitmproxy.http": http_mod,
                          "mitmproxy.net": net, "mitmproxy.net.encoding": encoding})

      spec = importlib.util.spec_from_file_location("mitm_logger", sys.argv[1])
      logger = importlib.util.module_from_spec(spec)
      spec.loader.exec_module(logger)

      class Headers(dict):
          def get(self, key, default=None):
              return next((v for k, v in self.items() if k.lower() == key.lower()), default)

      for f in json.load(sys.stdin):
          req = types.SimpleNamespace(host=f["host"], path=f["path"], method="POST", scheme="https", port=443,
                                      url="https://" + f["host"] + f["path"],
                                      headers=Headers({"content-type": "application/json"}),
                                      raw_content=f["request"].encode())
          resp = types.SimpleNamespace(status_code=200, headers=Headers({"content-type": "application/json"}),
                                       raw_content=None, stream=None)
          flow = types.SimpleNamespace(request=req, response=resp, metadata={})
          logger.request(flow)
          logger.responseheaders(flow)
          if callable(resp.stream):
              resp.stream(f["response"].encode())
          elif resp.stream is not True:
              resp.raw_content = f["response"].encode()
          logger.response(flow)
    PYTHON

    # Each flow is a request to `host` + `path` and its answer; returns the log's entries.
    def log(flows, env)
      Dir.mktmpdir("mitm-logger") do |dir|
        path = File.join(dir, "http.log")
        _out, err, status = Open3.capture3(
          env.merge("MITM_LOG_PATH" => path, "AIXLE_REDACT_LIST" => File.join(dir, "none")),
          "python3", "-I", "-c", HARNESS, LOGGER, stdin_data: flows.to_json
        )
        assert status.success?, err
        File.exist?(path) ? File.readlines(path).map { |line| JSON.parse(line) } : []
      end
    end

    def flow(host, path, request: %({"input":"the whole conversation"}), response: %({"usage":{"total":1}}))
      { host: host, path: path, request: request, response: response }
    end

    def body(entries, direction, path)
      entries.find { |e| e["direction"] == direction && e["path"] == path }&.fetch("body")
    end

    test "keeps only the bodies its rules name, and the size of every other one" do
      entries = log([ flow("runtime.us-east-1.kiro.dev", "/v1/responses") ],
                    "MITM_TRACKED_DOMAINS" => "kiro.dev", "MITM_LOG_BODIES" => "response:kiro.dev/v1/responses")

      assert_equal "<omitted: not logged>", body(entries, "request", "/v1/responses")
      assert_equal %({"usage":{"total":1}}), body(entries, "response", "/v1/responses")
      request = entries.find { |e| e["direction"] == "request" }
      assert_equal %({"input":"the whole conversation"}).bytesize, request["content_length"]
    end

    test "counts a dropped response body instead of holding it" do
      entries = log([ flow("cli-chat-proxy.grok.com", "/v1/bundle/archive", response: "x" * 4_096) ],
                    "MITM_TRACKED_DOMAINS" => "grok.com", "MITM_LOG_BODIES" => "none")

      response = entries.find { |e| e["direction"] == "response" }
      assert_equal "<omitted: not logged>", response["body"]
      assert_equal 4_096, response["content_length"]
    end

    test "keeps every body when the platform does not say, as before the setting existed" do
      entries = log([ flow("api.anthropic.com", "/v1/messages") ], "MITM_TRACKED_DOMAINS" => "api.anthropic.com")

      assert_equal %({"input":"the whole conversation"}), body(entries, "request", "/v1/messages")
      assert_equal %({"usage":{"total":1}}), body(entries, "response", "/v1/messages")
    end

    test "logs no host when the tracked list is empty, and every host when there is none" do
      assert_empty log([ flow("files.pythonhosted.org", "/packages/x.whl") ], "MITM_TRACKED_DOMAINS" => "")
      assert_equal 2, log([ flow("files.pythonhosted.org", "/packages/x.whl") ], {}).size
    end

    test "logs a tracked domain's subdomains and nothing outside it" do
      env = AntigravityCliAdapter.new.mitm_env

      entries = log([ flow("daily-cloudcode-pa.googleapis.com", "/v1internal:loadCodeAssist"),
                      flow("storage.googleapis.com", "/bucket/layer.tar.gz") ], env)

      assert_equal [ "daily-cloudcode-pa.googleapis.com" ], entries.pluck("host").uniq
    end

    # The bodies each usage parser reads, logged with that adapter's own settings and
    # handed to its parser: a rule that misses its path costs the session its usage.
    test "keeps the response credits Kiro prices a session from" do
      adapter = KiroCliAdapter.new
      sse = "data: #{{ type: 'response.completed', response: { id: 'r1', status: 'completed', model: 'auto',
                                                              usage: { 'kiro:credits' => { value: 0.5 } } } }.to_json}\n\n"

      entries = log([ flow("runtime.us-east-1.kiro.dev", "/v1/responses", response: sse) ], adapter.mitm_env)
      credits = adapter.send(:response_credits, entries.map(&:to_json).join("\n"))

      assert_equal [ 0.5 ], credits.pluck(:credits)
      assert_equal "<omitted: not logged>", body(entries, "request", "/v1/responses")
    end

    test "keeps the completions Grok prices a session from, on either login's host" do
      env = GrokAdapter.new.mitm_env
      usage = %({"usage":{"prompt_tokens":10,"completion_tokens":5}})

      entries = log([ flow("cli-chat-proxy.grok.com", "/v1/responses", response: usage),
                      flow("api.x.ai", "/v1/chat/completions", response: usage),
                      flow("cli-chat-proxy.grok.com", "/v1/bundle/archive", response: "binary") ], env)

      assert_equal usage, body(entries, "response", "/v1/responses")
      assert_equal usage, body(entries, "response", "/v1/chat/completions")
      assert_equal "<omitted: not logged>", body(entries, "response", "/v1/bundle/archive")
      assert(entries.select { |e| e["direction"] == "request" }.all? { |e| e["body"] == "<omitted: not logged>" })
    end

    test "keeps the metrics Codex falls back to for usage, and drops its catalogue answers" do
      env = CodexAdapter.new.mitm_env

      entries = log([ flow("ab.chatgpt.com", "/otlp/v1/metrics", request: %({"resourceMetrics":[]})),
                      flow("chatgpt.com", "/backend-api/codex/responses"),
                      flow("chatgpt.com", "/backend-api/ps/mcp") ], env)

      assert_equal %({"resourceMetrics":[]}), body(entries, "request", "/otlp/v1/metrics")
      assert_equal %({"usage":{"total":1}}), body(entries, "response", "/backend-api/codex/responses")
      assert_equal "<omitted: not logged>", body(entries, "response", "/backend-api/ps/mcp")
    end
  end
end
