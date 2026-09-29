# frozen_string_literal: true

require "test_helper"

# Every agent- and person-facing tool, called by a member of company A with ids
# that belong to company B, must neither change B's data nor hand any of it back.
#
# The ids are read from each tool's own input schema, so a tool is covered the
# day it is added: every `*_id` / `*_ids` parameter that names a tenant-owned
# record is tried with B's record while the rest of the call is A's. Every B
# record carries MARKER in a field a tool would echo back, and the whole call runs
# inside a savepoint that is rolled back, so the calls cannot affect each other.
class CrossTenantToolsTest < ActiveSupport::TestCase
  MARKER = "zzforeigntenant"
  SIBLING = "zzsiblingproject"
  # A sibling project shares its company, its people and its integrations with
  # the session's own, so those ids are not a boundary there.
  SHARED_WITH_SIBLING = %i[company user integration].freeze

  # Parameter name -> the world record it names. Anything else ending in _id is
  # an external identifier (an Azure work item, a Coder job) and is left alone.
  ID_PARAMS = {
    "project_id" => :project, "target_project_id" => :project, "scope_id" => :project,
    "company_id" => :company, "assignee_id" => :user,
    "workflow_id" => :workflow, "step_id" => :step, "step_ids" => :step, "depends_on_step_ids" => :step,
    "sub_step_id" => :sub_step, "sub_step_ids" => :sub_step,
    "run_id" => :run, "step_run_id" => :step_run, "session_id" => :session,
    "agent_id" => :agent,
    "tool_id" => :tool, "tool_ids" => :tool, "base_tool_ids" => :tool,
    "skill_id" => :skill, "skill_ids" => :skill, "base_skill_ids" => :skill,
    "mcp_server_id" => :mcp_server, "mcp_server_ids" => :mcp_server, "base_mcp_server_ids" => :mcp_server,
    "repository_id" => :repository, "repository_ids" => :repository, "base_repository_ids" => :repository,
    "config_item_id" => :config_item, "config_item_ids" => :config_item, "base_config_item_ids" => :config_item,
    "asset_id" => :asset, "asset_ids" => :asset, "base_asset_ids" => :asset, "resource_id" => :asset,
    "integration_id" => :integration,
    "column_id" => :column, "column_ids" => :column, "board_column_id" => :column, "subject_column_id" => :column,
    "task_id" => :task, "entity_id" => :task,
    "trigger_id" => :trigger, "binding_id" => :column_binding,
    "tool_result_id" => :tool_result
  }.freeze

  setup do
    mock_temporal_start
    TemporalService.stubs(:send_signal).returns({ ok: true })
    TemporalService.stubs(:cancel_workflow).returns({ ok: true })
    Rails.logger.stubs(:info)
    Rails.logger.stubs(:warn)
    Rails.logger.stubs(:error)

    @a = world("alpha")
    @b = world(MARKER)
    @user = @a[:user]
  end

  test "no personal tool reads or changes another company's records through an id" do
    failures = probe(classes(PersonalTools::Base), minimum: 50) do |klass, params|
      klass.new(params: params, user: @user).execute
    end

    assert_empty failures, failures.join("\n")
  end

  test "no internal tool reads or changes another company's records through an id" do
    failures = probe(classes(InternalTools::Base), minimum: 30) do |klass, params|
      klass.new(params: params, session: @a[:session]).execute
    end

    assert_empty failures, failures.join("\n")
  end

  # The Builder runs the personal tools as its user, who may well reach other
  # projects of the same company. Only the pin keeps the agent inside the
  # session's project, so the foreign world here is a sibling project of the
  # same company and the same user.
  test "no builder tool reaches a sibling project its user can also reach" do
    @b = sibling_world(SIBLING)
    builder = create(:terminal_session, :agent_session, :running, user: @user, project: @a[:project],
                                                                  metadata: { "aixle_builder" => true })
    entries = Tools::BuilderToolset.definitions.map do |defn|
      [ defn.name.to_s, Tools::BuilderToolset.input_schema(defn), defn ]
    end

    failures = probe(entries, minimum: 50, marker: SIBLING, skip: SHARED_WITH_SIBLING) do |defn, params|
      Tools::BuilderToolset.execute(defn, params, builder)
    end

    assert_empty failures, failures.join("\n")
  end

  private

  # entries: [name, input schema, what the block is handed to call it].
  def probe(entries, minimum:, marker: MARKER, skip: [])
    failures = []
    probed = 0
    entries.each do |name, schema, callable|
      schema ||= {}
      properties = schema["properties"] || {}
      properties.each_key do |param|
        next unless ID_PARAMS.key?(param)
        next if skip.include?(ID_PARAMS[param])

        probed += 1
        params = call_params(properties, schema["required"] || [], foreign: param)
        outcome = isolated do
          before = fingerprint(@b, shared: skip)
          result = begin
            yield(callable, params)
          rescue StandardError => e
            { refused: "#{e.class}: #{e.message}" }
          end
          problem = leak(result, marker) || change(before, fingerprint(@b, shared: skip))
          "#{name}(#{param}): #{problem}" if problem
        end
        failures << outcome if outcome
      end
    end
    assert_operator probed, :>, minimum, "the probe reached too few parameters to mean anything"
    failures
  end

  def classes(base)
    Rails.application.eager_load!
    base.descendants.select { |klass| klass.respond_to?(:tool_defined?) && klass.tool_defined? }
        .sort_by(&:name)
        .map { |klass| [ klass.name, klass.tool_definition.input_schema, klass ] }
  end

  # The call is A's in every respect but the one parameter under test.
  def call_params(properties, required, foreign:)
    properties.each_with_object({}) do |(name, spec), params|
      world = name == foreign ? @b : @a
      if ID_PARAMS.key?(name)
        value = id_for(world, ID_PARAMS[name], spec)
        params[name] = spec["type"] == "array" ? [ value ] : value
      elsif required.include?(name)
        params[name] = filler(name, spec)
      end
    end
  end

  def id_for(world, key, spec)
    record = world.fetch(key)
    return record.execution_id if key == :tool_result
    return record.id.to_s if spec["type"] == "string"

    record.id
  end

  def filler(name, spec)
    return spec["enum"].first if spec["enum"].present?

    case spec["type"]
    when "integer", "number" then 1
    when "boolean" then true
    when "array" then []
    when "object" then {}
    else name == "kind" ? "webhook" : "probe"
    end
  end

  def isolated
    outcome = nil
    ActiveRecord::Base.transaction(requires_new: true) do
      outcome = yield
      raise ActiveRecord::Rollback
    end
    outcome
  end

  def leak(result, marker)
    text = result.to_json
    "returned the other tenant's data: #{text.truncate(200)}" if text.include?(marker)
  end

  def change(before, after)
    changed = before.keys.select { |key| before[key] != after[key] }
    "changed the other tenant's #{changed.join(', ')}" if changed.any?
  end

  # What a tool acting on B would leave behind: its records' own state, and the
  # size of every collection hanging off B's project.
  def fingerprint(world, shared: [])
    records = %i[project workflow step sub_step run session tool skill mcp_server repository config_item
                 agent asset column task trigger column_binding integration] - shared
    state = records.to_h do |key|
      record = world[key]
      row = record.class.unscoped.where(id: record.id).pick(:updated_at)
      [ key, row&.to_f ]
    end
    project = world[:project]
    state.merge(
      workflows: Workflow.unscoped.where(project_id: project.id).count,
      steps: Step.unscoped.where(workflow_id: world[:workflow].id).count,
      sub_steps: SubStep.unscoped.where(step_id: world[:step].id).count,
      runs: WorkflowRun.where(project_id: project.id).count,
      sessions: shared.include?(:company) ? TerminalSession.where(project_id: project.id).count : TerminalSession.where(company_id: world[:company].id).count,
      tools: Tool.unscoped.where(project_id: project.id).count,
      skills: Skill.unscoped.where(project_id: project.id).count,
      mcp_servers: MCPServer.unscoped.where(project_id: project.id).count,
      agents: Agent.unscoped.where(project_id: project.id).count,
      config_items: ConfigItem.unscoped.where(project_id: project.id).count,
      repositories: Repository.unscoped.where(project_id: project.id).count,
      assets: Asset.unscoped.where(project_id: project.id).count,
      columns: BoardColumn.where(board_id: world[:column].board_id).count,
      tasks: BoardTask.unscoped.where(board_id: world[:column].board_id).count,
      triggers: TriggerBinding.where(project_id: project.id).count,
      column_bindings: ColumnWorkflowBinding.where(board_column_id: world[:column].id).count,
      collaborators: ProjectCollaborator.where(project_id: project.id).count
    )
  end

  def world(tag)
    company = create(:company, name: "#{tag} company")
    user = create(:user, :admin, :onboarding_completed, company: company, name: "#{tag} user")
    integration = create(:integration, company: company, connected_by: user, name: "#{tag}-org")
    project_world(tag, company: company, user: user, integration: integration)
  end

  def sibling_world(tag)
    project_world(tag, company: @a[:company], user: @a[:user], integration: @a[:integration])
  end

  def project_world(tag, company:, user:, integration:)
    project = create(:project, company: company, owner: user, name: "#{tag} project")
    workflow = create(:workflow, scope: project, name: "#{tag} workflow")
    step = create(:step, workflow: workflow, name: "#{tag} step", instructions: "#{tag} instructions",
                         allow_non_interactive: true)
    sub_step = create(:sub_step, step: step, name: "#{tag} sub step")
    run = create(:workflow_run, :running, workflow: workflow, project: project, user: user)
    session = create(:terminal_session, :agent_session, :running, user: user, project: project,
                                                                  initial_prompt: "#{tag} prompt")
    step_run = create(:step_run, workflow_run: run, step: step, terminal_session: session)
    tool = create(:tool, scope: project, name: "#{tag}_tool", display_name: "#{tag} tool")
    board = create(:board, project: project)
    column = create(:board_column, board: board, name: "#{tag} column")
    {
      company: company, user: user, project: project, workflow: workflow, step: step, sub_step: sub_step,
      run: run, session: session, step_run: step_run, tool: tool, integration: integration,
      skill: create(:skill, scope: project, name: "#{tag}-skill", title: "#{tag} skill"),
      mcp_server: create(:mcp_server, scope: project, name: "#{tag}-mcp"),
      repository: create(:repository, scope: project, integration: integration, full_name: "#{tag}/repo"),
      config_item: create(:config_item, scope: project, name: "#{tag.upcase}_KEY", value: "#{tag}-value"),
      agent: create(:agent, scope: project, name: "#{tag}_agent", title: "#{tag} agent"),
      asset: create(:asset, scope: project, created_by: user, name: "#{tag}.md"),
      column: column,
      task: create(:board_task, board: board, board_column: column, title: "#{tag} task"),
      trigger: create(:trigger_binding, project: project, workflow: workflow, created_by: user, name: "#{tag} trigger"),
      column_binding: ColumnWorkflowBinding.create!(board_column: column, workflow: workflow, created_by: user),
      tool_result: create(:tool_result, tool: tool, terminal_session: session, error: "#{tag} error")
    }
  end
end
