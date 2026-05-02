# frozen_string_literal: true

module InternalTools
  class MetaFinalizeWorkflow < Base
    include MetaToolHelpers

    def execute
      require_project_context!

      workflow = find_target_workflow!
      result = validate_workflow(workflow)
      errors_list = result[:errors]
      warnings_list = result[:warnings]

      if errors_list.empty?
        broadcast_meta_activity(
          action: "finalized_workflow",
          entity_type: "Workflow",
          entity_name: workflow.name,
          entity_id: workflow.id
        )

        response = {
          valid: true,
          workflow_id: workflow.id,
          workflow_name: workflow.name,
          summary: "Workflow '#{workflow.name}' is valid with #{workflow.steps.not_deleted.count} steps."
        }
        response[:warnings] = warnings_list if warnings_list.any?
        success(response.to_json)
      else
        response = {
          valid: false,
          workflow_id: workflow.id,
          workflow_name: workflow.name,
          errors: errors_list,
          summary: "Workflow '#{workflow.name}' has #{errors_list.size} validation error(s)."
        }
        response[:warnings] = warnings_list if warnings_list.any?
        success(response.to_json)
      end
    rescue RuntimeError => e
      error(e.message)
    end

    private

    def validate_workflow(workflow)
      errors = []
      warnings = []
      steps = workflow.steps.not_deleted.includes(:sub_steps, :agent).order(:position)

      errors << "Workflow has no steps" if steps.empty?

      bound_to_column = ColumnWorkflowBinding.exists?(workflow_id: workflow.id)

      steps.each do |step|
        errors << "Step '#{step.name}' (position #{step.position}) has no instructions" if step.instructions.blank?

        if step.agent_id.blank?
          warnings << "Step '#{step.name}' has no agent assigned — will use project default"
        elsif !Agent.exists?(step.agent_id)
          errors << "Step '#{step.name}' references non-existent agent_id #{step.agent_id}"
        end

        if bound_to_column && !step.allow_non_interactive
          errors << "Step '#{step.name}' must have allow_non_interactive: true (workflow is bound to a board column for auto-trigger)"
        end

        validate_linked_resources(step, errors)

        step.sub_steps.active.each do |ss|
          errors << "SubStep in step '#{step.name}' has no name" if ss.name.blank?
        end

        step.depends_on_step_ids.each do |dep_id|
          unless steps.any? { |s| s.id == dep_id }
            errors << "Step '#{step.name}' depends on non-existent step_id #{dep_id}"
          end
        end
      end

      errors << "Dependency graph contains a cycle" if has_cycle?(steps)

      if steps.any?
        positions = steps.map(&:position).sort
        expected = (positions.first..positions.first + positions.size - 1).to_a
        if positions != expected
          errors << "Step positions are not sequential: #{positions.inspect}"
        end
      end

      { errors: errors, warnings: warnings }
    end

    def validate_linked_resources(step, errors)
      if step.tool_ids.present?
        missing = step.tool_ids - Tool.not_deleted.where(id: step.tool_ids).pluck(:id)
        missing.each { |id| errors << "Step '#{step.name}' links non-existent tool_id #{id}" }
      end

      if step.skill_ids.present?
        missing = step.skill_ids - Skill.where(id: step.skill_ids).pluck(:id)
        missing.each { |id| errors << "Step '#{step.name}' links non-existent skill_id #{id}" }
      end

      if step.mcp_server_ids.present?
        missing = step.mcp_server_ids - MCPServer.where(id: step.mcp_server_ids).pluck(:id)
        missing.each { |id| errors << "Step '#{step.name}' links non-existent mcp_server_id #{id}" }
      end
    end

    def has_cycle?(steps)
      visited = Set.new
      in_stack = Set.new

      dfs = lambda do |step|
        return true if in_stack.include?(step.id)
        return false if visited.include?(step.id)

        visited.add(step.id)
        in_stack.add(step.id)

        step.depends_on_step_ids.each do |dep_id|
          dep_step = steps.find { |s| s.id == dep_id }
          next unless dep_step

          return true if dfs.call(dep_step)
        end

        in_stack.delete(step.id)
        false
      end

      steps.each { |s| return true if dfs.call(s) }
      false
    end
  end
end
