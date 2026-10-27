# frozen_string_literal: true

require "test_helper"

# FeaturesResource is the `features` shared prop and, through Typelizer, the
# `Features` type useFeatureFlag takes.
class FeaturesResourceTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
  end

  def shipped_client_keys
    FeatureFlags::Registry.load(FeatureFlags::REGISTRY_PATH).definitions.select(&:client?).map(&:key)
  end

  # Guards drift between config/feature_flags.yml and the generated Features type.
  test "its attributes are exactly the client: true flags of config/feature_flags.yml" do
    assert_equal shipped_client_keys.map(&:to_s).sort, FeaturesResource._attributes.keys.map(&:to_s).sort
    assert_includes shipped_client_keys, :external_runners
    assert_not FeaturesResource._attributes.key?(:coder_reap)
  end

  test "it carries exactly the client: true flags of config/feature_flags.yml" do
    assert_equal shipped_client_keys.map { |key| key.to_s.camelize(:lower) }.sort,
                 FeaturesResource.new(@company).to_h.keys.sort
    assert_not FeaturesResource.new(@company).to_h.key?("coderReap")
  end

  test "external_runners is off for a company without an override" do
    assert_not Feature.enabled?(:external_runners, company: @company)
    assert_equal({ "externalRunners" => false }, FeaturesResource.new(@company).to_h.slice("externalRunners"))
  end

  test "external_runners is on for a company with the override, and only for it" do
    other = create(:company)

    with_feature(:external_runners, true, company: @company) do
      assert Feature.enabled?(:external_runners, company: @company)
      assert_equal({ "externalRunners" => true }, FeaturesResource.new(@company).to_h.slice("externalRunners"))
      assert_equal({ "externalRunners" => false }, FeaturesResource.new(other).to_h.slice("externalRunners"))
    end
  end

  test "no company reads the global value" do
    with_feature(:external_runners, true) do
      assert_equal({ "externalRunners" => true }, FeaturesResource.new(nil).to_h.slice("externalRunners"))
    end
  end
end
