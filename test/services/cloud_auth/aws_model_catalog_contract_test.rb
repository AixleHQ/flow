# frozen_string_literal: true

require "test_helper"

module CloudAuth
  # Pins FakeAwsModelCatalog to the real catalog's surface (docs/testing.md R4). No network.
  class AwsModelCatalogContractTest < ActiveSupport::TestCase
    CONSTRUCTOR_KEYWORDS = %i[access_key_id region secret_access_key session_token].freeze

    test "the fake implements the real catalog's public surface" do
      assert_equal [ :inference_profiles ], AwsModelCatalog.public_instance_methods(false)
      assert_includes FakeAwsModelCatalog.public_instance_methods(false), :inference_profiles
    end

    test "both take the same constructor keywords" do
      assert_equal CONSTRUCTOR_KEYWORDS,
                   AwsModelCatalog.instance_method(:initialize).parameters.map(&:last).sort
      assert_equal CONSTRUCTOR_KEYWORDS,
                   FakeAwsModelCatalog.instance_method(:initialize).parameters.map(&:last).sort
    end

    test "the fake returns the real Profile value object" do
      assert_instance_of AwsModelCatalog::Profile, build_fake.inference_profiles.first
    end

    # Claude Code accepts a system-defined profile by id, but an application profile only by
    # ARN — an application profile's id is not a routable model name.
    test "a system profile is addressed by id and an application profile by arn" do
      arn = "arn:aws:bedrock:us-east-1:111122223333:application-inference-profile/abc"

      assert_equal "us.anthropic.claude-sonnet-4-6",
                   FakeAwsModelCatalog.system_profile("us.anthropic.claude-sonnet-4-6").model_id
      assert_equal arn, FakeAwsModelCatalog.application_profile(arn, name: "Flow").model_id
    end

    test "anthropic? distinguishes what Claude Code can actually run" do
      assert_predicate FakeAwsModelCatalog.system_profile("us.anthropic.claude-sonnet-4-6"), :anthropic?
      assert_not_predicate FakeAwsModelCatalog.non_anthropic_profile("us.amazon.nova-2"), :anthropic?
    end

    test "scripted failures raise CloudAuth errors, never vendor errors" do
      catalog = build_fake
      catalog.raise_on_list = DeniedError

      assert_kind_of CloudAuth::Error, assert_raises(DeniedError) { catalog.inference_profiles }
    end

    # == the real catalog against the real API shape (docs/testing.md R4) ==

    # ListInferenceProfiles with no typeEquals answers with system-defined profiles ONLY, so
    # an account's own application profiles have to be asked for by name. Getting this wrong
    # hid exactly the profiles an enterprise account grants InvokeModel on, and offered a
    # list of system profiles it was not permitted to call.
    test "both profile types are asked for, and application profiles come back" do
      stub_list("APPLICATION", [ application_summary ])
      stub_list("SYSTEM_DEFINED", [ system_summary ])

      profiles = build_real.inference_profiles

      assert_requested :get, list_url("APPLICATION")
      assert_requested :get, list_url("SYSTEM_DEFINED")
      assert_equal %w[APPLICATION SYSTEM_DEFINED], profiles.map(&:type)
      assert_equal [ APP_ARN, "us.anthropic.claude-sonnet-4-6" ], profiles.map(&:model_id)
    end

    test "a profile that is not ACTIVE is never offered" do
      stub_list("APPLICATION", [ application_summary.merge("status" => "INACTIVE") ])
      stub_list("SYSTEM_DEFINED", [])

      assert_empty build_real.inference_profiles
    end

    test "pagination follows nextToken within one type" do
      second = application_summary(arn: "#{APP_ARN}-2", name: "Insights")
      stub_request(:get, list_url("APPLICATION"))
        .to_return(status: 200, body: { "inferenceProfileSummaries" => [ application_summary ],
                                        "nextToken" => "page-2" }.to_json)
      stub_request(:get, "#{list_url('APPLICATION')}&nextToken=page-2")
        .to_return(status: 200, body: { "inferenceProfileSummaries" => [ second ] }.to_json)
      stub_list("SYSTEM_DEFINED", [])

      assert_equal 2, build_real.inference_profiles.size
    end

    # A permission set may allow listing the account's own profiles and nothing else — that
    # is an answer, not a failure, and it is the answer such a deployment wants.
    test "one type being denied still yields what the other returned" do
      stub_list("APPLICATION", [ application_summary ])
      stub_denied("SYSTEM_DEFINED")

      profiles = build_real.inference_profiles

      assert_equal [ APP_ARN ], profiles.map(&:model_id)
    end

    test "every type denied raises DeniedError, never a vendor error" do
      stub_denied("APPLICATION")
      stub_denied("SYSTEM_DEFINED")

      assert_raises(DeniedError) { build_real.inference_profiles }
    end

    private

    APP_ARN = "arn:aws:bedrock:us-east-1:111122223333:application-inference-profile/abc123"

    def build_fake
      FakeAwsModelCatalog.new(region: "us-east-1", access_key_id: "A", secret_access_key: "S", session_token: "T")
    end

    def build_real
      AwsModelCatalog.new(region: "us-east-1", access_key_id: "AKIAFAKE",
                          secret_access_key: "secret", session_token: "token")
    end

    def list_url(type)
      "https://bedrock.us-east-1.amazonaws.com/inference-profiles?maxResults=100&type=#{type}"
    end

    def stub_list(type, summaries)
      stub_request(:get, list_url(type))
        .to_return(status: 200, body: { "inferenceProfileSummaries" => summaries }.to_json)
    end

    def stub_denied(type)
      stub_request(:get, list_url(type)).to_return(
        status: 403,
        headers: { "x-amzn-ErrorType" => "AccessDeniedException" },
        body: { "message" => "User is not authorized to perform bedrock:ListInferenceProfiles" }.to_json
      )
    end

    # The payload shape ListInferenceProfiles really returns for an account's own profile.
    def application_summary(arn: APP_ARN, name: "dbp-aixle-flow-opus-4-8")
      {
        "inferenceProfileArn" => arn,
        "inferenceProfileId" => arn.split("/").last,
        "inferenceProfileName" => name,
        "type" => "APPLICATION",
        "status" => "ACTIVE",
        "createdAt" => "2026-07-01T00:00:00Z",
        "updatedAt" => "2026-07-01T00:00:00Z",
        "models" => [
          { "modelArn" => "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-opus-4-8" }
        ]
      }
    end

    def system_summary(id: "us.anthropic.claude-sonnet-4-6")
      {
        "inferenceProfileArn" => "arn:aws:bedrock:us-east-1::inference-profile/#{id}",
        "inferenceProfileId" => id,
        "inferenceProfileName" => "US Anthropic Claude Sonnet 4.6",
        "type" => "SYSTEM_DEFINED",
        "status" => "ACTIVE",
        "createdAt" => "2026-07-01T00:00:00Z",
        "updatedAt" => "2026-07-01T00:00:00Z",
        "models" => [
          { "modelArn" => "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-sonnet-4-6" }
        ]
      }
    end
  end
end
