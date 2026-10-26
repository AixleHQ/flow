# frozen_string_literal: true

require "test_helper"

# FeaturesResource is the `features` shared prop and, through Typelizer, the
# `Features` type useFeatureFlag takes. It runs against the shipped registry.
class FeaturesResourceTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
  end

  def shipped_client_keys
    FeatureFlags::Registry.load(FeatureFlags::REGISTRY_PATH).definitions.select(&:client?).map { |d| d.key.to_s.camelize(:lower) }
  end

  test "it carries exactly the client: true flags of config/feature_flags.yml" do
    assert_equal shipped_client_keys.sort, FeaturesResource.new(@company).to_h.keys.sort
    assert_includes shipped_client_keys, "externalRunners"
    assert_not FeaturesResource.new(@company).to_h.key?("coderReap")
  end

  test "external_runners is off for a company without an override" do
    assert_not Feature.enabled?(:external_runners, company: @company)
    refute FeaturesResource.new(@company).to_h["externalRunners"]
  end

  test "external_runners is on for a company with the override, and only for it" do
    other = create(:company)

    with_feature(:external_runners, true, company: @company) do
      assert Feature.enabled?(:external_runners, company: @company)
      assert FeaturesResource.new(@company).to_h["externalRunners"]
      refute FeaturesResource.new(other).to_h["externalRunners"]
    end
  end

  test "no company reads the global value" do
    with_feature(:external_runners, true) do
      assert FeaturesResource.new(nil).to_h["externalRunners"]
    end
  end
end
