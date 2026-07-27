# frozen_string_literal: true

# Canonical fake for CloudAuth::AwsBedrockProbe. Never stub Aws::BedrockRuntime directly
# (docs/testing.md §4, R2/R3). Kept interface-identical by
# test/services/cloud_auth/aws_bedrock_probe_contract_test.rb.
#
#   probe = FakeAwsBedrockProbe.new(region: "us-east-1", access_key_id: "A",
#                                   secret_access_key: "S", session_token: "T")
#   probe.failure = { code: "AccessDeniedException", message: "..." }
class FakeAwsBedrockProbe
  Result = CloudAuth::AwsBedrockProbe::Result

  attr_reader :region, :access_key_id, :secret_access_key, :session_token, :probed_models
  attr_accessor :failure

  def initialize(region:, access_key_id:, secret_access_key:, session_token:)
    @region = region
    @access_key_id = access_key_id
    @secret_access_key = secret_access_key
    @session_token = session_token
    @probed_models = []
    @failure = nil
  end

  def probe(model_id:)
    @probed_models << model_id
    if @failure
      Result.new(ok: false, model_id: model_id,
                 error_code: @failure[:code], error_message: @failure[:message])
    else
      Result.new(ok: true, model_id: model_id, error_code: nil, error_message: nil)
    end
  end
end
