# frozen_string_literal: true

# The `features` shared prop: every flag config/feature_flags.yml declares
# `client: true`, as the current company resolves it, and nothing else.
#
#   FeaturesResource.new(current_company).to_h   # nil company: an anonymous page
#
# The attributes are read from the registry, so this one class produces both the
# payload and the generated `Features` type that useFeatureFlag takes: declaring
# a client flag is the only step, and there is no frontend list to keep in sync.
# The registry is read when the class loads (it is fixed after boot), so a test
# registry swapped in later does not change the attributes.
class FeaturesResource < ApplicationResource
  FeatureFlags.registry.definitions.select(&:client?).each do |definition|
    typelize :boolean
    attribute(definition.key) { |company| FeatureFlags.client_value(definition, company: company) }
  end
end
