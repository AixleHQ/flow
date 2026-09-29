# frozen_string_literal: true

require "test_helper"

# Staging is where production's configuration is tried out, so every setting
# production.yml makes, staging.yml makes too — one only production.yml makes
# (Temporal on, say) would leave staging running without it.
class SettingsParityTest < ActiveSupport::TestCase
  test "staging sets every key production sets" do
    missing = key_paths(settings("production")) - key_paths(settings("staging"))

    assert_empty missing, "config/settings/staging.yml lacks: #{missing.join(', ')}"
  end

  private

  def settings(env)
    YAML.safe_load(ERB.new(Rails.root.join("config/settings/#{env}.yml").read).result) || {}
  end

  def key_paths(hash, prefix = nil)
    hash.flat_map do |key, value|
      path = [ prefix, key ].compact.join(".")
      value.is_a?(Hash) ? key_paths(value, path) : [ path ]
    end
  end
end
