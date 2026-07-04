# frozen_string_literal: true

require "test_helper"

class Tools::DefinitionDSLTest < ActiveSupport::TestCase
  def build_definition(&block)
    builder = Tools::DefinitionDSL::Builder.new("sample_tool")
    builder.instance_eval(&block)
    Tools::Definition.new(**builder.to_h.merge(handler_class_name: "InternalTools::ReadToolResult"))
  end

  test "param sugar compiles to JSON Schema" do
    definition = build_definition do
      display_name "Sample"
      description "Sample tool"
      param :status, type: :string, enum: %w[open closed], required: true,
                     description: "New status"
      param :count, type: :integer, default: 1
    end

    assert_equal(
      {
        "type" => "object",
        "properties" => {
          "status" => { "type" => "string", "description" => "New status", "enum" => %w[open closed] },
          "count" => { "type" => "integer", "default" => 1 }
        },
        "required" => %w[status]
      },
      definition.input_schema
    )
  end

  test "raw input_schema stringifies keys and wins over param sugar" do
    definition = build_definition do
      display_name "Sample"
      input_schema(type: "object", properties: { id: { type: "integer" } }, required: %i[id])
    end

    assert_equal "integer", definition.input_schema.dig("properties", "id", "type")
    assert_equal [ "id" ], definition.input_schema["required"]
  end

  test "unknown injection rule raises at class-definition time" do
    error = assert_raises(ArgumentError) do
      build_definition { inject_when :on_full_moon }
    end
    assert_match(/on_full_moon/, error.message)
  end

  test "definitions are frozen and reload-safe (class name string, not class object)" do
    definition = build_definition { display_name "Sample" }

    assert definition.frozen?
    assert definition.tags.frozen?
    assert_equal "InternalTools::ReadToolResult", definition.handler_class_name
    assert_equal InternalTools::ReadToolResult, definition.handler_class
  end
end
