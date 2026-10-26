# frozen_string_literal: true

# The `features` shared prop: every flag config/feature_flags.yml declares
# `client: true`, as the current company resolves it, and nothing else.
#
#   FeaturesResource.new(current_company).to_h   # nil company: an anonymous page
#
# One class produces both the payload and the generated `Features` type that
# useFeatureFlag takes: declaring a client flag is the only step, and there is no
# frontend list to keep in sync.
#
# The two halves have different lifetimes, and that is the seam this class keeps:
#
# - The attribute list is a build-time artifact. Typelizer generates `Features.ts`
#   from the declared attributes, so the schema must be static: it is read from the
#   shipped registry file, never from the swappable FeatureFlags.registry, and so
#   cannot depend on which registry was current when the class loaded.
# - The values are dynamic and resolve per request through the current registry.
#   A key that registry does not declare is left out of the payload rather than
#   raised (`SharedProps.features` is `Partial<Features>`, so an absent key is
#   type-correct).
class FeaturesResource < ApplicationResource
  FeatureFlags::Registry.load(FeatureFlags::REGISTRY_PATH).definitions.select(&:client?).each do |definition|
    typelize :boolean
    attribute(definition.key) do |company|
      current = FeatureFlags.registry
      next Alba::REMOVE_KEY unless current.declared?(definition.key)

      FeatureFlags.client_value(current.fetch(definition.key), company: company)
    end
  end
end
