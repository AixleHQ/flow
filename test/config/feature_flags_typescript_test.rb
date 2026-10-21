# frozen_string_literal: true

require "test_helper"

# app/frontend/types/generated/featureFlags.ts is what makes a misspelled flag
# name fail `tsc`, so it must list exactly the client flags the registry declares.
class FeatureFlagsTypescriptTest < ActiveSupport::TestCase
  test "the committed featureFlags.ts matches config/feature_flags.yml" do
    shipped = FeatureFlags::Registry.load(FeatureFlags::REGISTRY_PATH)

    assert_equal FeatureFlags::Typescript.render(shipped), FeatureFlags::Typescript::OUTPUT_PATH.read,
      "run `bin/rails feature_flags:typescript` and commit app/frontend/types/generated/featureFlags.ts"
  end

  test "an empty registry is a valid, empty union" do
    source = FeatureFlags::Typescript.render(FeatureFlags::Registry.new({}))

    assert_includes source, "export type FeatureFlagName = never;\n"
  end

  test "only client flags are listed, camelized as the features prop delivers them" do
    source = FeatureFlags::Typescript.render(FeatureFlags::Registry.load(FeatureFlagsHelper::EXAMPLE_REGISTRY))

    assert_includes source, "export type FeatureFlagName =\n  | 'boardAiSummary';\n"
    assert_not_includes source, "coderReap"
    assert_not_includes source, "coder_reap"
  end

  test "names are sorted, so the file only changes when the set does" do
    entry = { "description" => "A flag.", "owner" => "@AixleHQ/web", "kind" => "ops", "scope" => "global",
              "default" => false, "client" => true }
    registry = FeatureFlags::Registry.new("zeta_panel" => entry, "alpha_panel" => entry)

    assert_includes FeatureFlags::Typescript.render(registry),
                    "export type FeatureFlagName =\n  | 'alphaPanel'\n  | 'zetaPanel';\n"
  end

  test "write puts the rendered file where it is asked to" do
    Dir.mktmpdir do |dir|
      path = Pathname(dir).join("generated/featureFlags.ts")
      registry = FeatureFlags::Registry.load(FeatureFlagsHelper::EXAMPLE_REGISTRY)

      FeatureFlags::Typescript.write(path, registry: registry)

      assert_equal FeatureFlags::Typescript.render(registry), path.read
    end
  end
end
