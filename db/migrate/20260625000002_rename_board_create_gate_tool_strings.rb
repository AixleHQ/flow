# frozen_string_literal: true

# The waits -> gates rename (20260623000007) updated the tool's `name` to
# board_create_gate but left its user-facing strings and JSON schema untouched:
# display_name "Board Create Wait", description "Create a Wait...", and an
# input_schema that still advertises the `wait_type` parameter. The executor
# (InternalTools::BoardCreateGate) reads `params[:gate_type]`, so the seeded
# schema was out of sync with the code. Seeds are not re-run on existing
# environments, so realign the already-seeded record here.
class RenameBoardCreateGateToolStrings < ActiveRecord::Migration[8.1]
  class MigrationTool < ActiveRecord::Base
    self.table_name = "tools"
  end

  GATE_DESC = "Create a Gate on a board task. The auto-workflow for the task's column will not fire until all Gates are resolved."
  WAIT_DESC = "Create a Wait on a board task. The auto-workflow for the task's column will not fire until all Waits are resolved."
  GATE_TYPE_DESC = "Gate type. Supported: github_checks_completed, github_workflow_completed"
  WAIT_TYPE_DESC = "Wait type. Supported: github_checks_completed, github_workflow_completed"

  def up
    rename_param(from: "wait_type", to: "gate_type",
                 display_name: "Board Create Gate", description: GATE_DESC, type_desc: GATE_TYPE_DESC)
  end

  def down
    rename_param(from: "gate_type", to: "wait_type",
                 display_name: "Board Create Wait", description: WAIT_DESC, type_desc: WAIT_TYPE_DESC)
  end

  private

  def rename_param(from:, to:, display_name:, description:, type_desc:)
    tool = MigrationTool.find_by(name: "board_create_gate")
    return unless tool

    schema = tool.input_schema || {}
    props = schema["properties"] || {}

    moved = props.delete(from) || props[to] || { "type" => "string" }
    moved["description"] = type_desc
    props[to] = moved
    schema["properties"] = props
    schema["required"] = Array(schema["required"]).map { |r| r == from ? to : r }

    tool.update_columns(display_name: display_name, description: description, input_schema: schema)
  end
end
