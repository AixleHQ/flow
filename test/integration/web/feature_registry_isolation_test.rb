# frozen_string_literal: true

require "test_helper"

# A test registry (with_feature_registry) reaches the requests the test makes,
# and nothing else: it is fiber-local, so a request served on another thread,
# or a list memoised there while it is active, reads the shipped registry.
# Before, the swap was process-global for the length of the test, and anything
# that memoised a flag list meanwhile (FeaturesResource's attribute list, task
# #178) kept test-only keys that raised UnknownFlag on a later request.
class Web::FeatureRegistryIsolationTest < ActionDispatch::IntegrationTest
  def shipped_client_flags = FeatureFlags::Registry.load(FeatureFlags::REGISTRY_PATH).definitions.select(&:client?).map(&:key)

  def features_prop(path)
    get path, headers: { "X-Inertia" => "true" }
    assert_response :success
    response.parsed_body.dig("props", "features")
  end

  test "a web request under a test registry cannot leave a test-only flag in a memoised list" do
    memoised = nil
    served_elsewhere = nil

    with_feature_registry(FeatureFlagsHelper::EXAMPLE_REGISTRY) do
      assert_equal({ "boardAiSummary" => false }, features_prop(login_path), "the test's own request sees its registry")

      # What a server thread or a class body evaluated on another thread
      # computes while the test registry is active on this one.
      memoised = Thread.new { FeatureFlags.registry.definitions.select(&:client?).map(&:key) }.value
      served_elsewhere = Thread.new do
        Rack::MockRequest.new(Rails.application).get(login_path, "HTTP_X_INERTIA" => "true")
      end.value
    end

    assert_equal shipped_client_flags, memoised
    assert_not_includes memoised, :board_ai_summary
    assert_equal 200, served_elsewhere.status
    assert_not JSON.parse(served_elsewhere.body).dig("props", "features").to_h.key?("boardAiSummary")

    # Every memoised key is declared, so resolving the list on the next request does not raise.
    assert_nothing_raised { memoised.each { |key| FeatureFlags.registry.fetch(key) } }
    assert_equal shipped_client_flags.size, features_prop(login_path).to_h.size
  end
end
