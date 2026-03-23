# frozen_string_literal: true

class WorkflowDuplicator
  def initialize(source_workflow, target_scope:)
    @source = source_workflow
    @target_scope = target_scope
  end

  def duplicate!
    ActiveRecord::Base.transaction do
      new_workflow = @target_scope.workflows.create!(
        name: unique_name,
        description: @source.description,
        config: @source.config
      )

      @source.steps.active.order(:position).each do |step|
        duplicate_step(step, new_workflow)
      end

      new_workflow
    end
  end

  private

  def unique_name
    base = @source.name
    existing = @target_scope.workflows.active.where("name LIKE ?", "#{base}%").pluck(:name)
    return base unless existing.include?(base)

    counter = 1
    counter += 1 while existing.include?("#{base} (#{counter})")
    "#{base} (#{counter})"
  end

  def duplicate_step(step, workflow)
    new_step = workflow.steps.create!(
      name: step.name,
      description: step.description,
      instructions: step.instructions,
      position: step.position,
      agent_id: step.agent_id,
      allow_non_interactive: step.allow_non_interactive,
      skip_policy: step.skip_policy,
      on_failure: step.on_failure,
      max_retries: step.max_retries,
      input_asset_specs: step.input_asset_specs,
      output_asset_specs: step.output_asset_specs,
      tool_ids: step.tool_ids,
      mcp_server_ids: step.mcp_server_ids,
      skill_ids: step.skill_ids,
      mount_repositories: step.mount_repositories
    )

    step.sub_steps.active.each do |ss|
      new_step.sub_steps.create!(
        name: ss.name,
        description: ss.description,
        instructions: ss.instructions,
        position: ss.position,
        required: ss.required
      )
    end
  end
end
