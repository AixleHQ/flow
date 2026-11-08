# frozen_string_literal: true

require "test_helper"

# Runners::ProtocolSchema: the gateway's request schemas in
# runner/protocol/schemas/v1/ (runner/protocol/PROTOCOL.md §5). The gateway's
# refusals themselves are tested through its routes and the conformance
# fixtures.
class Runners::ProtocolSchemaTest < ActiveSupport::TestCase
  test "every schema file is named, and every named schema is a valid JSON Schema" do
    files = Runners::ProtocolSchema::DIRECTORY.glob("*.json").map { |path| path.basename(".json").to_s }

    assert_equal Runners::ProtocolSchema::SCHEMAS.sort, files.sort
    Runners::ProtocolSchema::SCHEMAS.each do |name|
      assert JSONSchemer.valid_schema?(JSON.parse(Runners::ProtocolSchema.path(name).read)), "#{name} is not a valid schema"
    end
  end

  test "an unknown schema is an error, not a pass" do
    assert_raises(ArgumentError) { Runners::ProtocolSchema.valid?("nope", {}) }
  end

  test "an op result needs a known status; a null field counts as absent, and an error is exactly class and message" do
    valid = [ { "status" => "ok" }, { "status" => "expired", "exit_code" => nil, "error" => nil },
              { "status" => "error", "exit_code" => 2, "stdout" => "", "stderr" => "x", "data" => { "a" => 1 },
                "error" => { "class" => "Timeout", "message" => "late" }, "unknown" => 1 } ]
    invalid = [ {}, { "status" => "done" }, { "status" => nil }, { "status" => "ok", "exit_code" => "0" },
                { "status" => "ok", "exit_code" => 1.5 }, { "status" => "ok", "stdout" => [ "x" ] },
                { "status" => "ok", "data" => "x" }, { "status" => "error", "error" => { "class" => "Timeout" } },
                { "status" => "error", "error" => { "class" => "Timeout", "message" => "late", "detail" => "x" } } ]

    valid.each { |body| assert Runners::ProtocolSchema.valid?("op_result.request", body), body.inspect }
    invalid.each { |body| assert_not Runners::ProtocolSchema.valid?("op_result.request", body), body.inspect }
  end

  test "a registration needs a string name and an object for facts; an os or arch that is not a string passes" do
    valid = [ { "name" => "build-01" }, { "name" => " ", "facts" => {} }, { "name" => "b", "os" => 7, "arch" => true },
              { "name" => "b", "os" => "o" * 255 } ]
    invalid = [ {}, { "name" => 5 }, { "name" => nil }, { "name" => "b", "facts" => nil }, { "name" => "b", "facts" => "x" },
                { "name" => "b", "os" => "o" * 256 }, { "name" => "b", "arch" => "a" * 256 } ]

    valid.each { |body| assert Runners::ProtocolSchema.valid?("register.request", body), body.inspect }
    invalid.each { |body| assert_not Runners::ProtocolSchema.valid?("register.request", body), body.inspect }
  end

  test "the long-poll's after and wait are non-negative integers, after within the bigint range" do
    valid = [ {}, { "after" => 0, "wait" => 0 }, { "after" => (2**63) - 1, "wait" => 600 } ]
    invalid = [ { "after" => -1 }, { "wait" => -1 }, { "after" => 2**63 }, { "after" => "1" }, { "wait" => "soon" } ]

    valid.each { |query| assert Runners::ProtocolSchema.valid?("ops.query", query), query.inspect }
    invalid.each { |query| assert_not Runners::ProtocolSchema.valid?("ops.query", query), query.inspect }
  end
end
