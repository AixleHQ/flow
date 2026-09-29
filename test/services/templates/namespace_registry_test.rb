# frozen_string_literal: true

require "test_helper"

class Templates::NamespaceRegistryTest < ActiveSupport::TestCase
  test "reads publishers and matches owners case-insensitively" do
    registry = Templates::NamespaceRegistry.parse(<<~YAML)
      - { name: acme, display_name: Acme Corp, verified: true, owners: [Acme-Bot] }
      - { name: globex, owners: [globex-dev] }
    YAML

    assert_empty registry.errors
    assert_equal %w[acme globex], registry.names
    assert registry.owner?("acme", "acme-bot")
    assert_not registry.owner?("acme", "globex-dev")
    assert_equal [ "globex", false ], [ registry["globex"].display_name, registry["globex"].verified ]
  end

  test "reports malformed entries instead of accepting them" do
    registry = Templates::NamespaceRegistry.parse(<<~YAML)
      - { name: Acme Corp, owners: [acme-bot] }
      - { name: globex }
      - { name: initech, owners: ["not a login"] }
    YAML

    assert_empty registry.names
    assert_equal 3, registry.errors.size
    assert(registry.errors.any? { |e| e.include?("needs at least one owner") })
  end
end
