# frozen_string_literal: true

require "test_helper"

# Golden parity gate for the code-first registry migration: the registry must
# reproduce, byte-for-byte at the JSON level, every tool the legacy
# db/seeds/platform_tools.rb seeded. The fixture was dumped from the seeds
# file's actual output before its deletion — regenerate it ONLY if a
# definition change is intentional (edit the fixture by hand or via a tool
# block change; there is no seeds file to re-dump anymore).
#
# Scaffolding: delete this test once the legacy kind column is dropped and
# the cutover has baked in production.
class PlatformToolsParityTest < ActiveSupport::TestCase
  test "registry reproduces the legacy seeds output exactly" do
    expected = JSON.parse(file_fixture("platform_tools_parity.json").read)
    definitions = Tools::Registry.definitions

    assert_equal expected.map { |t| t["name"] }.sort, definitions.keys.sort,
                 "Tool name sets diverged between legacy seeds fixture and registry"

    expected.each do |seeded|
      definition = definitions.fetch(seeded["name"])
      row = definition.to_row_attributes

      assert_equal seeded["display_name"], row[:display_name], "display_name mismatch for #{seeded['name']}"
      assert_equal seeded["description"], row[:description], "description mismatch for #{seeded['name']}"
      assert_equal seeded["kind"], row[:kind], "legacy kind mismatch for #{seeded['name']}"
      assert_equal seeded["execution_mode"], row[:execution_mode], "execution_mode mismatch for #{seeded['name']}"
      assert_equal seeded["requires_integration"], row[:requires_integration],
                   "requires_integration mismatch for #{seeded['name']}"
      assert_equal seeded["input_schema"].as_json, row[:input_schema].as_json,
                   "input_schema mismatch for #{seeded['name']}"
    end
  end
end
