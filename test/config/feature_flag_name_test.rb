# frozen_string_literal: true

require "test_helper"

# FeatureFlagName in app/frontend/shared/ui/types.ts is written by hand, and it
# is what makes a misspelled flag fail `tsc`. It must name exactly the client
# flags the registry declares, as the `features` prop camelizes them.
class FeatureFlagNameTest < ActiveSupport::TestCase
  TYPES = Rails.root.join("app/frontend/shared/ui/types.ts")
  DECLARATION = /^export type FeatureFlagName =(?<union>[^;]*);$/

  def declared_names(source)
    match = DECLARATION.match(source)
    assert match, "no `export type FeatureFlagName = ...;` declaration"

    union = match[:union].strip
    return [] if union == "never"

    members = union.split("|").map(&:strip).reject(&:empty?)
    names = members.filter_map { |member| member[/\A'(\w+)'\z/, 1] }
    assert_equal members.size, names.size, "FeatureFlagName members must be quoted names: #{union.inspect}"
    names.sort
  end

  test "FeatureFlagName lists exactly the client flags of config/feature_flags.yml" do
    shipped = FeatureFlags::Registry.load(FeatureFlags::REGISTRY_PATH)
    expected = shipped.definitions.select(&:client?).map { |definition| definition.key.to_s.camelize(:lower) }.sort

    # Once a client flag exists, the hand-written list is no longer the only fix: say so where it is read.
    resource_hint =
      if expected.any?
        ". Now that a client flag exists, consider replacing the hand-written list instead: an Alba " \
          "resource with the client flags as `typelize :boolean` attributes lets Typelizer generate a " \
          "`Features` interface for `useFeatureFlag(name: keyof Features)`, with no drift test. See the " \
          "comment above FeatureFlagName in app/frontend/shared/ui/types.ts"
      end

    assert_equal expected, declared_names(TYPES.read),
      "update FeatureFlagName in app/frontend/shared/ui/types.ts to the client: true flags " \
      "(#{expected.empty? ? 'none: `never`' : expected.map { |name| "'#{name}'" }.join(' | ')})#{resource_hint}"
  end

  test "a union of names reads as those names, on one line or several" do
    assert_equal %w[boardAiSummary newSidebar],
                 declared_names("export type FeatureFlagName = 'newSidebar' | 'boardAiSummary';\n")
    assert_equal %w[boardAiSummary newSidebar],
                 declared_names("export type FeatureFlagName =\n  | 'boardAiSummary'\n  | 'newSidebar';\n")
  end
end
