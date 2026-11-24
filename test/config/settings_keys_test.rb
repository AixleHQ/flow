# frozen_string_literal: true

require "test_helper"

# YAML keeps the last of two equal keys without a word: a second top-level `auth:`
# in config/settings.yml dropped AUTH_ENABLED_KINDS on every deployment.
class SettingsKeysTest < ActiveSupport::TestCase
  FILES = [ Rails.root.join("config/settings.yml"), *Rails.root.glob("config/settings/*.yml") ].freeze

  test "no settings file repeats a key within one mapping" do
    FILES.each do |file|
      assert_empty duplicate_keys(Psych.parse(ERB.new(file.read).result)), file.basename.to_s
    end
  end

  test "AUTH_ENABLED_KINDS reaches the auth settings" do
    auth = auth_settings_with("AUTH_ENABLED_KINDS" => "password,google")

    assert_equal "password,google", auth["enabled_kinds"]
    assert_includes auth.keys, "session_idle_timeout_hours"
  end

  private

  def duplicate_keys(node, path = [])
    return node.children.to_a.flat_map { |child| duplicate_keys(child, path) } unless node.is_a?(Psych::Nodes::Mapping)

    pairs = node.children.each_slice(2).to_a
    repeated = pairs.map { |key, _| key.value }.tally.select { |_, count| count > 1 }.keys
    repeated.map { |key| (path + [ key ]).join(".") } +
      pairs.flat_map { |key, value| duplicate_keys(value, path + [ key.value ]) }
  end

  def auth_settings_with(env)
    saved = env.keys.index_with { |name| ENV.fetch(name, nil) }
    env.each { |name, value| ENV[name] = value }
    YAML.safe_load(ERB.new(Rails.root.join("config/settings.yml").read).result, aliases: true).fetch("auth")
  ensure
    saved.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
  end
end
