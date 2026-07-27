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

    private

    def build_fake
      FakeAwsModelCatalog.new(region: "us-east-1", access_key_id: "A", secret_access_key: "S", session_token: "T")
    end
  end
end
