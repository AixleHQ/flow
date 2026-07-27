# frozen_string_literal: true

require "aws-sdk-bedrockruntime"

module CloudAuth
  # App-owned seam over a single Bedrock InvokeModel call, used only to answer "can this
  # connection actually invoke a model?".
  #
  # It exists because Claude Code hides Bedrock errors: without this the difference
  # between a broken credential, a permission set with no bedrock:InvokeModel, and a
  # model that was never enabled in the account all look identical to the user — an
  # agent that never answers. So this deliberately returns the provider's message
  # VERBATIM rather than a friendly one.
  #
  # Per docs/testing.md §4 the vendor SDK is never stubbed; tests stub this class and use
  # FakeAwsBedrockProbe.
  class AwsBedrockProbe
    # One token in, one token out. A health check that costs real money is a health check
    # nobody runs, and max_tokens is what Bedrock reserves quota by.
    PROBE_BODY = {
      anthropic_version: "bedrock-2023-05-31",
      max_tokens: 1,
      messages: [ { role: "user", content: "." } ]
    }.freeze

    Result = Data.define(:ok, :model_id, :error_code, :error_message) do
      def ok? = ok
    end

    def initialize(region:, access_key_id:, secret_access_key:, session_token:)
      @region = region
      @access_key_id = access_key_id
      @secret_access_key = secret_access_key
      @session_token = session_token
    end

    def probe(model_id:)
      client.invoke_model(model_id: model_id, content_type: "application/json", body: PROBE_BODY.to_json)
      Result.new(ok: true, model_id: model_id, error_code: nil, error_message: nil)
    rescue ::Aws::BedrockRuntime::Errors::ServiceError => e
      # Pass the provider's own wording through. "on-demand throughput isn't supported"
      # and "AccessDeniedException" are the two the user has to act on, and paraphrasing
      # them loses the part that says what to fix.
      Result.new(ok: false, model_id: model_id, error_code: e.code.to_s, error_message: e.message.to_s)
    rescue ::Aws::Errors::ServiceError, Seahorse::Client::NetworkingError => e
      Result.new(ok: false, model_id: model_id,
                 error_code: e.class.name.demodulize, error_message: e.message.to_s)
    end

    private

    def client
      @client ||= ::Aws::BedrockRuntime::Client.new(
        region: @region,
        credentials: ::Aws::Credentials.new(@access_key_id, @secret_access_key, @session_token),
        retry_limit: 0
      )
    end
  end
end
