# frozen_string_literal: true

module PersonalTools
  class ValidateWorkflow < Base
    tool do
      display_name "Validate Workflow"
      description "Check a workflow before it runs: every step has instructions, linked agents, " \
                  "tools, skills, MCP servers, assets, repositories and config items exist and are " \
                  "enabled in this project, dependencies form no cycle, and every step allows " \
                  "non-interactive runs when a trigger launches the workflow unattended. " \
                  "Returns errors (must fix) and warnings (worth a look)."
      audience :user
      tags :workflows
      read_only
      param :project_id, type: :integer, description: "Project id.", required: true
      param :workflow_id, type: :integer, description: "Workflow id.", required: true
    end

    LINKS = {
      tool_ids: ->(project) { Tool.visible_for_project(project) },
      skill_ids: ->(project) { Skill.visible_for_project(project) },
      mcp_server_ids: ->(project) { MCPServer.visible_for_project(project) },
      asset_ids: ->(project) { Asset.visible_for_project(project) },
      repository_ids: ->(project) { Repository.visible_for_project(project) },
      config_item_ids: ->(project) { ConfigItem.visible_for_project(project) }
    }.freeze

    def execute
      project = find_project!
      authorize!(project, :show?, policy: Web::Company::Projects::WorkflowsPolicy, project: project)
      workflow = find_workflow!(project)

      errors = []
      warnings = []
      steps = workflow.steps.not_deleted.includes(:sub_steps).order(:position).to_a
      errors << "Workflow has no steps" if steps.empty?
      unattended = unattended_triggers(workflow)

      steps.each do |step|
        errors << "Step '#{step.name}' has no instructions" if step.instructions.blank?
        check_agent(project, step, errors, warnings)
        check_links(project, step, errors)
        if unattended.any? && !step.allow_non_interactive
          errors << "Step '#{step.name}' must allow non-interactive runs — the workflow is launched " \
                    "unattended by #{unattended.to_sentence}"
        end
        missing_deps = step.depends_on_step_ids - steps.map(&:id)
        missing_deps.each { |id| errors << "Step '#{step.name}' depends on step #{id}, which is not in this workflow" }
      end
      errors << "Step dependencies form a cycle" if cycle?(steps)

      success(workflow_id: workflow.id, name: workflow.name, valid: errors.empty?,
              steps_count: steps.size, errors: errors, warnings: warnings)
    end

    private

    def unattended_triggers(workflow)
      columns = workflow.column_workflow_bindings.where(trigger_mode: "auto").includes(:board_column)
                        .map { |b| "board column '#{b.board_column.name}'" }
      events = workflow.trigger_bindings.where(enabled: true).map { |b| "trigger '#{b.name.presence || b.event_type}'" }
      columns + events
    end

    def check_agent(project, step, errors, warnings)
      if step.agent_id.blank?
        warnings << "Step '#{step.name}' has no agent — it runs with the default persona"
      elsif !Agent.visible_for_project(project).exists?(step.agent_id)
        errors << "Step '#{step.name}' uses agent #{step.agent_id}, which is not an agent of this project"
      end
    end

    def check_links(project, step, errors)
      LINKS.each do |field, visible|
        ids = Array(step.public_send(field)).map(&:to_i)
        next if ids.empty?

        (ids - visible.call(project).where(id: ids).pluck(:id)).each do |id|
          errors << "Step '#{step.name}' links #{field.to_s.delete_suffix('_ids').tr('_', ' ')} " \
                    "#{id}, which is missing, disabled or not in this project"
        end
      end
    end

    def cycle?(steps)
      by_id = steps.index_by(&:id)
      state = {}
      visit = lambda do |step|
        return true if state[step.id] == :visiting
        return false if state[step.id] == :done

        state[step.id] = :visiting
        cyclic = step.depends_on_step_ids.any? { |dep| by_id[dep] && visit.call(by_id[dep]) }
        state[step.id] = :done
        cyclic
      end
      steps.any? { |step| visit.call(step) }
    end
  end
end
