# frozen_string_literal: true

require "test_helper"

class InstructionReferencesTest < ActiveSupport::TestCase
  TEXT = "Read {{asset:12}} and {{output:45:reports/summary.md}}, then ask {{mcp:7}} about {{step:new-3}}."

  test "scans each reference with its type and id" do
    refs = InstructionReferences.scan(TEXT)

    assert_equal %w[asset output mcp step], refs.map(&:type)
    assert_equal [ 12, "45", 7, "new-3" ], refs.map(&:id)
    assert_equal "reports/summary.md", refs[1].name
    assert refs.all?(&:valid?)
  end

  test "tools, skills and config items are referenced by id like assets and servers" do
    refs = InstructionReferences.scan("Run {{tool:3}} with {{skill:4}}, reading {{config_item:5}}; not {{config_item:API_KEY}}.")

    assert_equal [ [ "tool", 3 ], [ "skill", 4 ], [ "config_item", 5 ], [ "config_item", nil ] ], refs.map { |r| [ r.type, r.id ] }
  end

  test "a body that does not parse is a reference that is not valid" do
    refs = InstructionReferences.scan("{{asset:brand}} {{output:45:}} {{step:-1}}")

    assert_equal 3, refs.size
    refute refs.any?(&:valid?)
  end

  test "rewrite replaces what the block returns and keeps the rest" do
    rewritten = InstructionReferences.rewrite(TEXT) { |ref| "<#{ref.type}>" if ref.type == "asset" }

    assert_equal "Read <asset> and {{output:45:reports/summary.md}}, then ask {{mcp:7}} about {{step:new-3}}.", rewritten
  end

  test "braces that are not references are reported, references are not" do
    text = "Use {{artifact_name}}, {{ Extract Revenue }} and {{asset:1}}; {{artifact_name}} again."

    assert_equal [ "{{artifact_name}}", "{{ Extract Revenue }}" ], InstructionReferences.unknown_braces(text)
  end
end
