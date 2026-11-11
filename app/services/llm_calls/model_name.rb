# frozen_string_literal: true

module LlmCalls
  # The one place a model id reported by a runtime becomes the canonical id stored on
  # llm_calls and looked up in the price table: a routing prefix ("openai/gpt-5",
  # "models/gemini-2.5-pro") and Bedrock's inference-profile region and vendor prefixes
  # ("us.anthropic.claude-sonnet-4-5-…") are removed; nothing else is touched.
  module ModelName
    BEDROCK_REGION = /\A(?:us|eu|apac|au|ca|jp|us-gov|global)\./
    BEDROCK_VENDOR = /\A(?:anthropic|meta|amazon|mistral|cohere|ai21|deepseek|openai|qwen|writer)\./
    ROUTING_PREFIX = %r{\A[^/]+/}
    BEDROCK_ARN = %r{\Aarn:aws[^:]*:bedrock:[^/]+/(?<id>.+)\z}

    module_function

    def canonical(raw)
      name = raw.to_s.strip
      return nil if name.empty? || name == "unknown"

      name = name[BEDROCK_ARN, :id] || name
      name = name.sub(ROUTING_PREFIX, "") while name.match?(ROUTING_PREFIX)
      name.sub(BEDROCK_REGION, "").sub(BEDROCK_VENDOR, "")
    end

    def bedrock?(raw)
      name = raw.to_s
      name.match?(BEDROCK_ARN) || name.sub(BEDROCK_REGION, "").match?(/\Aanthropic\./)
    end
  end
end
