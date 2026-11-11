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

  test "a registration needs a string name and an object for facts; an os or arch is an optional string" do
    valid = [ { "name" => "build-01" }, { "name" => " ", "facts" => {} },
              { "name" => "b", "os" => "o" * 255, "arch" => "amd64" } ]
    not_strings = [ 7, true, nil, {}, [ "linux" ] ].flat_map do |value|
      [ { "name" => "b", "os" => value }, { "name" => "b", "arch" => value } ]
    end
    invalid = [ {}, { "name" => 5 }, { "name" => nil }, { "name" => "b", "facts" => nil }, { "name" => "b", "facts" => "x" },
                { "name" => "b", "os" => "o" * 256 }, { "name" => "b", "arch" => "a" * 256 } ] + not_strings

    valid.each { |body| assert Runners::ProtocolSchema.valid?("register.request", body), body.inspect }
    invalid.each { |body| assert_not Runners::ProtocolSchema.valid?("register.request", body), body.inspect }
  end

  # PROTOCOL.md §5.1: the gateway refuses such a body as ephemeral_not_supported, before its other fields.
  test "a registration with ephemeral true passes whatever the rest of it holds; one without, does not" do
    asks = [ { "ephemeral" => true }, { "ephemeral" => true, "name" => 5, "facts" => nil } ]
    does_not = [ false, nil, 0, 0.0, 1, "true", "" ].map { |value| { "ephemeral" => value, "name" => 5 } }

    asks.each { |body| assert Runners::ProtocolSchema.valid?("register.request", body), body.inspect }
    does_not.each { |body| assert_not Runners::ProtocolSchema.valid?("register.request", body), body.inspect }
  end

  test "a registration's ephemeral is a JSON boolean: any other value is refused, even with a valid body" do
    assert Runners::ProtocolSchema.valid?("register.request", { "name" => "b" })
    assert Runners::ProtocolSchema.valid?("register.request", { "name" => "b", "ephemeral" => false })
    [ "true", "false", 1, 0, 0.0, 1.0, nil, "" ].each do |value|
      assert_not Runners::ProtocolSchema.valid?("register.request", { "name" => "b", "ephemeral" => value }), value.inspect
    end
  end

  test "the long-poll's after and wait are non-negative integers, after within the bigint range" do
    valid = [ {}, { "after" => 0, "wait" => 0 }, { "after" => (2**63) - 1, "wait" => 600 } ]
    invalid = [ { "after" => -1 }, { "wait" => -1 }, { "after" => 2**63 }, { "after" => "1" }, { "wait" => "soon" } ]

    valid.each { |query| assert Runners::ProtocolSchema.valid?("ops.query", query), query.inspect }
    invalid.each { |query| assert_not Runners::ProtocolSchema.valid?("ops.query", query), query.inspect }
  end
end

class Runners::ProtocolSchemaReleasesTest < ActiveSupport::TestCase
  test "a registration's auto_update is true or false" do
    assert Runners::ProtocolSchema.valid?("register.request", { "name" => "b", "auto_update" => false })
    assert Runners::ProtocolSchema.valid?("register.request", { "name" => "b", "auto_update" => true })
    [ nil, "false", 0 ].each do |value|
      assert_not Runners::ProtocolSchema.valid?("register.request", { "name" => "b", "auto_update" => value }), value.inspect
    end
  end

  test "a release names a strict semantic version and an os-arch platform" do
    valid = [ { "version" => "0.1.0" }, { "version" => "1.5.0-rc.1+build.7", "platform" => "linux-amd64" },
              { "version" => "1.4.0", "platform" => "darwin-arm64" } ]
    invalid = [ {}, { "version" => "v1.4.0" }, { "version" => "1.4" }, { "version" => "01.2.3" }, { "version" => "1.2.3-01" },
                { "version" => "1.4.0", "platform" => "linux" }, { "version" => "1.4.0", "platform" => "Linux-AMD64" },
                { "version" => "1.4.0", "platform" => "linux-amd64/../x" } ]

    valid.each { |params| assert Runners::ProtocolSchema.valid?("releases.params", params), params.inspect }
    invalid.each { |params| assert_not Runners::ProtocolSchema.valid?("releases.params", params), params.inspect }
  end
end
