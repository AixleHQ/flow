# frozen_string_literal: true

module InternalTools
  class MetaFinalizeWorkflow < Base
    include MetaToolHelpers

    def execute
      require_workflow_context!

      workflow = find_target_workflow!
      errors_list = validate_workflow(workflow)

      if errors_list.empty?
        broadcast_meta_activity(
          action: "finalized_workflow",
          entity_type: "Workflow",
          entity_name: workflow.name,
          entity_id: workflow.id
        )

        success({
          valid: true,
          workflow_id: workflow.id,
          workflow_name: workflow.name,
          summary: "Workflow '#{workflow.name}' is valid with #{workflow.steps.not_deleted.count} steps."
        }.to_json)
      else
        success({
          valid: false,
          workflow_id: workflow.id,
          workflow_name: workflow.name,
          errors: errors_list,
          summary: "Workflow '#{workflow.name}' has #{errors_list.size} validation issue(s)."
        }.to_json)
      end
    rescue RuntimeError => e
      error(e.message)
    end

    private

    def validate_workflow(workflow)
      errors = []
      steps = workflow.steps.not_deleted.includes(:sub_steps, :agent).order(:position)

      errors << "Workflow has no steps" if steps.empty?

      steps.each do |step|
        errors << "Step '#{step.name}' (position #{step.position}) has no instructions" if step.instructions.blank?

        if step.agent_id.present? && !Agent.exists?(step.agent_id)
          errors << "Step '#{step.name}' references non-existent agent_id #{step.agent_id}"
        end

        step.sub_steps.active.each do |ss|
          errors << "SubStep in step '#{step.name}' has no name" if ss.name.blank?
        end

        # Check dependency references
        step.depends_on_step_ids.each do |dep_id|
          unless steps.any? { |s| s.id == dep_id }
            errors << "Step '#{step.name}' depends on non-existent step_id #{dep_id}"
          end
        end
      end

      # Check for cycles in dependency graph
      errors << "Dependency graph contains a cycle" if has_cycle?(steps)

      # Check positions are sequential
      if steps.any?
        positions = steps.map(&:position).sort
        expected = (positions.first..positions.first + positions.size - 1).to_a
        if positions != expected
          errors << "Step positions are not sequential: #{positions.inspect}"
        end
      end

      errors
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
