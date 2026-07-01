# frozen_string_literal: true

class WorkflowDuplicator
  # #duplicate! returns the new Workflow (backwards-compatible). A summary of the
  # resources that were NOT copied / need manual setup is exposed afterwards via
  # #summary so the controller can surface a "needs setup" notice (see #302).
  def initialize(source_workflow, target_scope:, name: nil)
    @source = source_workflow
    @target_scope = target_scope
    @name = name
  end

  attr_reader :summary

  def duplicate!
    @summary = nil

    workflow = ActiveRecord::Base.transaction do
      @dep_copier = DependencyCopier.new(source: @source, target_project: target_project)

      new_workflow = @target_scope.workflows.create!(
        name: available_name,
        description: @source.description,
        config: remapped_config(@source.config.deep_dup)
      )

      step_id_map = {}
      step_pairs = []

      @source.steps.not_deleted.order(:position).each do |step|
        new_step = duplicate_step(step, new_workflow)
        step_id_map[step.id] = new_step.id
        step_pairs << [ step, new_step ]
      end

      step_pairs.each do |source_step, new_step|
        next if source_step.depends_on_step_ids.blank?

        remapped = source_step.depends_on_step_ids.filter_map { |old_id| step_id_map[old_id] }
        new_step.update!(depends_on_step_ids: remapped)
      end

      new_workflow
    end

    @summary = @dep_copier.summary if @dep_copier && target_project
    workflow
  end

  private

  # nil unless we're copying into a Project (in-company duplicate / catalog copy).
  # When nil (e.g. duplicating to a Company scope for publish/seed), every map_*
  # is an identity function, preserving the pre-#302 behavior exactly.
  def target_project
    @target_scope if @target_scope.is_a?(Project)
  end

  def remapped_config(config)
    return config unless target_project

    config["base_tool_ids"]       = @dep_copier.map_tool_ids(config["base_tool_ids"])             if config["base_tool_ids"]
    config["base_skill_ids"]      = @dep_copier.map_skill_ids(config["base_skill_ids"])           if config["base_skill_ids"]
    config["base_mcp_server_ids"] = @dep_copier.map_mcp_server_ids(config["base_mcp_server_ids"]) if config["base_mcp_server_ids"]
    # base_asset_ids intentionally NOT remapped — assets are out of scope (D5).
    config
  end

  def available_name
    base = @name.presence || @source.name
    existing = @target_scope.workflows.active.where("workflows.name LIKE ?", "#{base}%").pluck(:name)
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
      agent_id: @dep_copier.map_agent_id(step.agent_id),
      allow_non_interactive: step.allow_non_interactive,
      skip_policy: step.skip_policy,
      on_failure: step.on_failure,
      max_retries: step.max_retries,
      preferred_model: step.preferred_model,
      bmad_enabled: step.bmad_enabled,
      required_agent_runtime: step.required_agent_runtime,
      input_asset_specs: step.input_asset_specs,
      output_asset_specs: step.output_asset_specs,
      tool_ids: @dep_copier.map_tool_ids(step.tool_ids),
      mcp_server_ids: @dep_copier.map_mcp_server_ids(step.mcp_server_ids),
      skill_ids: @dep_copier.map_skill_ids(step.skill_ids),
      asset_ids: step.asset_ids, # unchanged — assets are out of scope (D5)
      mount_repositories: step.mount_repositories,
      depends_on_step_ids: []
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

    new_step
  end
end
