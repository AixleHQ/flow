# frozen_string_literal: true

# Brings the seeded Aixle Builder prompt surfaces that live in the DB in line with the
# updated seeds (seeds do not re-run on existing installs). Three records carry verbosity
# language that pushes the builder toward bloated step instructions:
#   1. the `meta_create_step` tool — its `instructions` param description (shown via tools/list)
#   2. the `workflow_architect` agent — persona + principles
#   3. the "Build Workflow" step of the "Aixle Builder" workflow — its instructions
# All updates are guarded so the migration is a no-op where the records are absent
# (e.g. a schema-only test DB that never loaded seeds).
class SimplifyAixleBuilderPrompts < ActiveRecord::Migration[8.0]
  META_STEP_OLD = "Detailed instructions for the agent (markdown)"
  META_STEP_NEW = "Focused, task-specific instructions (markdown): what to do and what to " \
                  "produce. Do NOT restate session-completion rules, workspace layout, " \
                  "sub-step tracking, or tool availability — the platform injects those " \
                  "automatically."

  PERSONA_OLD = "4. Write detailed step instructions (the CORE of each step)"
  PERSONA_NEW = "4. Write focused step instructions (the CORE of each step) — " \
                "the task-specific WHAT and OUTPUT only"

  PRINCIPLES_OLD = "3. Instructions should be detailed enough for the agent to work autonomously"
  PRINCIPLES_NEW = "3. Instructions should be specific and focused — say what to do and what " \
                   "to produce, and omit anything the platform already injects (completion " \
                   "rules, workspace layout, sub-step tracking, tool availability)"

  STEP_INSTR_OLD = "meta_create_step — for each step (write detailed instructions!)"
  STEP_INSTR_NEW = "meta_create_step — for each step (write focused, task-specific instructions)"

  STEP_IMPORTANT_OLD = "Step instructions are the MOST IMPORTANT thing — be detailed and specific."
  STEP_IMPORTANT_NEW = "Step instructions are LEAN and task-specific — state what to do and " \
                       "what to produce; never restate platform scaffolding (completion " \
                       "rules, workspace layout, sub-step tracking, tool availability)."

  def up
    update_meta_step_tool(META_STEP_NEW)
    update_workflow_architect(persona_from: PERSONA_OLD, persona_to: PERSONA_NEW,
                              principles_from: PRINCIPLES_OLD, principles_to: PRINCIPLES_NEW)
    update_build_workflow_step(
      { STEP_INSTR_OLD => STEP_INSTR_NEW, STEP_IMPORTANT_OLD => STEP_IMPORTANT_NEW }
    )
  end

  def down
    update_meta_step_tool(META_STEP_OLD)
    update_workflow_architect(persona_from: PERSONA_NEW, persona_to: PERSONA_OLD,
                              principles_from: PRINCIPLES_NEW, principles_to: PRINCIPLES_OLD)
    update_build_workflow_step(
      { STEP_INSTR_NEW => STEP_INSTR_OLD, STEP_IMPORTANT_NEW => STEP_IMPORTANT_OLD }
    )
  end

  private

  def update_meta_step_tool(description)
    tool = Tool.find_by(name: "meta_create_step", kind: "workflow")
    return unless tool&.input_schema&.dig("properties", "instructions")

    schema = tool.input_schema.deep_dup
    schema["properties"]["instructions"]["description"] = description
    tool.update!(input_schema: schema)
  end

  def update_workflow_architect(persona_from:, persona_to:, principles_from:, principles_to:)
    agent = Agent.find_by(scope_type: "System", scope_id: 0, name: "workflow_architect")
    return unless agent

    agent.update!(
      persona: agent.persona.to_s.gsub(persona_from, persona_to),
      principles: agent.principles.to_s.gsub(principles_from, principles_to)
    )
  end

  def update_build_workflow_step(replacements)
    build_workflow_steps.each do |step|
      instructions = step.instructions.to_s
      replacements.each { |from, to| instructions = instructions.gsub(from, to) }
      step.update!(instructions: instructions) unless instructions == step.instructions.to_s
    end
  end

  # The builder workflow is the only System-scoped workflow carrying a "Build Workflow" step.
  # Match by scope, NOT by name: pre-rebrand installs have it named "Palad Builder" while the
  # seed now creates "Aixle Builder", and no rename migration ever reconciled the two.
  def build_workflow_steps
    workflow_ids = Workflow.where(scope_type: "System", scope_id: 0).pluck(:id)
    return Step.none if workflow_ids.empty?

    Step.where(workflow_id: workflow_ids, name: "Build Workflow", deleted_at: nil)
  end
end
