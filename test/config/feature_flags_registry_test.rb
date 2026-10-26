# frozen_string_literal: true

require "test_helper"

# config/feature_flags.yml is valid. Deliberately no check on dates: a release
# flag past its remove_by gets a badge on /admin/feature_flags, because a test
# that turns red on a calendar date breaks unrelated PRs.
class FeatureFlagsRegistryTest < ActiveSupport::TestCase
  test "every entry of config/feature_flags.yml is valid" do
    assert_nothing_raised { FeatureFlags::Registry.load(FeatureFlags::REGISTRY_PATH) }
  end
end
