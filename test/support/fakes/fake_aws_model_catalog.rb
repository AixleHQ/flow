# frozen_string_literal: true

# Canonical fake for CloudAuth::AwsModelCatalog. Never stub Aws::Bedrock directly
# (docs/testing.md §4, R2/R3). Kept interface-identical by
# test/services/cloud_auth/aws_model_catalog_contract_test.rb.
#
#   catalog = FakeAwsModelCatalog.new(region: "us-east-1", access_key_id: "A",
#                                    secret_access_key: "S", session_token: "T")
#   catalog.profiles = [FakeAwsModelCatalog.system_profile("us.anthropic.claude-sonnet-4-6")]
#   catalog.raise_on_list = CloudAuth::DeniedError
class FakeAwsModelCatalog
  Profile = CloudAuth::AwsModelCatalog::Profile

  # A system-defined Claude profile, as an account sees it out of the box.
  def self.system_profile(id, name: nil, model_arn: nil)
    Profile.new(
      id: id, arn: "arn:aws:bedrock:us-east-1::inference-profile/#{id}",
      name: name || id, description: nil, type: "SYSTEM_DEFINED",
      model_arns: [ model_arn || "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-sonnet-4-6" ]
    )
  end

  # An account's own profile — the shape an enterprise deployment actually pins.
  def self.application_profile(arn, name:, model_arn: nil)
    Profile.new(
      id: arn.split("/").last, arn: arn, name: name, description: "Team profile",
      type: "APPLICATION",
      model_arns: [ model_arn || "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-opus-4-8" ]
    )
  end

  # Something the account has that Claude Code cannot run.
  def self.non_anthropic_profile(id)
    Profile.new(
      id: id, arn: "arn:aws:bedrock:us-east-1::inference-profile/#{id}", name: id,
      description: nil, type: "SYSTEM_DEFINED",
      model_arns: [ "arn:aws:bedrock:us-east-1::foundation-model/amazon.nova-2" ]
    )
  end

  attr_reader :region, :access_key_id, :secret_access_key, :session_token, :calls
  attr_accessor :profiles, :raise_on_list

  def initialize(region:, access_key_id:, secret_access_key:, session_token:)
    @region = region
    @access_key_id = access_key_id
    @secret_access_key = secret_access_key
    @session_token = session_token
    @calls = 0
    @profiles = [ self.class.system_profile("us.anthropic.claude-sonnet-4-6") ]
    @raise_on_list = nil
  end

  def inference_profiles
    @calls += 1
    raise @raise_on_list, "FakeAwsModelCatalog scripted failure" if @raise_on_list

    @profiles
  end
end
