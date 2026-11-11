# frozen_string_literal: true

require "test_helper"

module LlmCalls
  class ModelNameTest < ActiveSupport::TestCase
    test "a plain model id is left alone" do
      assert_equal "gpt-5.1-codex-max", ModelName.canonical("gpt-5.1-codex-max")
      assert_equal "claude-sonnet-4-5-20250929", ModelName.canonical("claude-sonnet-4-5-20250929")
    end

    test "routing prefixes are removed" do
      assert_equal "gpt-5", ModelName.canonical("openai/gpt-5")
      assert_equal "gemini-2.5-pro", ModelName.canonical("models/gemini-2.5-pro")
    end

    test "Bedrock region and vendor prefixes are removed, the version suffix is kept" do
      assert_equal "claude-sonnet-4-5-20250929-v1:0", ModelName.canonical("us.anthropic.claude-sonnet-4-5-20250929-v1:0")
      assert_equal "claude-opus-4-6-v1", ModelName.canonical("global.anthropic.claude-opus-4-6-v1")
      assert_equal "claude-haiku-4-5", ModelName.canonical("anthropic.claude-haiku-4-5")
      assert_equal "claude-sonnet-4-5", ModelName.canonical(
        "arn:aws:bedrock:us-east-1:123456789012:inference-profile/us.anthropic.claude-sonnet-4-5"
      )
    end

    test "no model is nil, not a name" do
      assert_nil ModelName.canonical(nil)
      assert_nil ModelName.canonical("  ")
      assert_nil ModelName.canonical("unknown")
    end

    test "a Bedrock id is recognised as one" do
      assert ModelName.bedrock?("us.anthropic.claude-sonnet-4-5-20250929-v1:0")
      assert ModelName.bedrock?("anthropic.claude-haiku-4-5")
      assert ModelName.bedrock?("arn:aws:bedrock:us-east-1:1:inference-profile/global.anthropic.claude-opus-4-6")
      assert_not ModelName.bedrock?("claude-sonnet-4-5")
      assert_not ModelName.bedrock?(nil)
    end
  end
end
