# frozen_string_literal: true

require "test_helper"

module CloudAuth
  # Pins FakeAwsBedrockProbe to the real probe's surface (docs/testing.md R4). Hits no
  # network: signatures and return shapes only.
  class AwsBedrockProbeContractTest < ActiveSupport::TestCase
    CONSTRUCTOR_KEYWORDS = %i[access_key_id region secret_access_key session_token].freeze

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

    private

    def build_fake
      FakeAwsBedrockProbe.new(region: "us-east-1", access_key_id: "A", secret_access_key: "S", session_token: "T")
    end

    def keywords(klass, name)
      klass.instance_method(name).parameters.select { |type, _| type == :keyreq }.map(&:last).sort
    end
  end
end
