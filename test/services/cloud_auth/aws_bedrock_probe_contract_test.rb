# frozen_string_literal: true

require "test_helper"

module CloudAuth
  # Pins FakeAwsBedrockProbe to the real probe's surface (docs/testing.md R4), and the real
  # probe to the InvokeModel API shape through WebMock.
  class AwsBedrockProbeContractTest < ActiveSupport::TestCase
    CONSTRUCTOR_KEYWORDS = %i[access_key_id region secret_access_key session_token].freeze
    MODEL_ID = "us.anthropic.claude-sonnet-4-6"

    test "the fake implements the real probe's public surface" do
      assert_equal [ :probe ], AwsBedrockProbe.public_instance_methods(false)
      assert_includes FakeAwsBedrockProbe.public_instance_methods(false), :probe
    end

    test "both take the same constructor keywords" do
      assert_equal CONSTRUCTOR_KEYWORDS, keywords(AwsBedrockProbe, :initialize)
      assert_equal CONSTRUCTOR_KEYWORDS, keywords(FakeAwsBedrockProbe, :initialize)
    end

    test "probe takes model_id in both" do
      assert_equal [ :model_id ], keywords(AwsBedrockProbe, :probe)
      assert_equal [ :model_id ], keywords(FakeAwsBedrockProbe, :probe)
    end

    test "the fake returns the real Result value object" do
      result = build_fake.probe(model_id: "us.anthropic.claude-sonnet-4-6")

      assert_instance_of AwsBedrockProbe::Result, result
      assert_predicate result, :ok?
      assert_nil result.error_message
    end

    # The whole point of the probe is that the provider's own wording reaches the user,
    # because that is the part that says what to fix.
    test "a scripted failure carries the provider code and message verbatim" do
      probe = build_fake
      probe.failure = { code: "AccessDeniedException", message: "User is not authorized to perform bedrock:InvokeModel" }

      result = probe.probe(model_id: "m")

      assert_not_predicate result, :ok?
      assert_equal "AccessDeniedException", result.error_code
      assert_equal "User is not authorized to perform bedrock:InvokeModel", result.error_message
    end

    # A health check that costs real money is a health check nobody runs.
    test "the probe body asks for a single token" do
      assert_equal 1, AwsBedrockProbe::PROBE_BODY[:max_tokens]
    end

    # == the real probe against the real API shape (docs/testing.md R4) ==

    # Each retry would be another billed invoke_model and another backoff before the user
    # sees the answer. Since aws-sdk-core 3.267 the SDK's default is three attempts.
    test "a throttled probe is not retried, and the provider code reaches the result" do
      stub_request(:post, invoke_url).to_return(
        status: 429,
        headers: { "x-amzn-ErrorType" => "ThrottlingException" },
        body: { "message" => "Too many requests, please wait before trying again." }.to_json
      )

      result = build_real.probe(model_id: MODEL_ID)

      assert_requested :post, invoke_url, times: 1
      assert_not_predicate result, :ok?
      assert_equal "ThrottlingException", result.error_code
    end

    test "an answering model is a passing probe" do
      stub_request(:post, invoke_url).to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: { "type" => "message", "content" => [ { "type" => "text", "text" => "." } ] }.to_json
      )

      assert_predicate build_real.probe(model_id: MODEL_ID), :ok?
    end

    private

    def invoke_url
      "https://bedrock-runtime.us-east-1.amazonaws.com/model/#{MODEL_ID}/invoke"
    end

    def build_real
      AwsBedrockProbe.new(region: "us-east-1", access_key_id: "AKIAFAKE",
                          secret_access_key: "secret", session_token: "token")
    end

    def build_fake
      FakeAwsBedrockProbe.new(region: "us-east-1", access_key_id: "A", secret_access_key: "S", session_token: "T")
    end

    def keywords(klass, name)
      klass.instance_method(name).parameters.select { |type, _| type == :keyreq }.map(&:last).sort
    end
  end
end
