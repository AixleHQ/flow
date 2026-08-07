# frozen_string_literal: true

class SessionConfigResolver
  attr_reader :session

  def self.resolve(session)
    new(session).resolve
  end

  def self.resolve_with_breakdown(session)
    new(session).resolve_with_breakdown
  end

  def initialize(session)
    @session = session
  end

  def resolve
    {
      session_type: session_type,
      agent_runtime: resolve_agent_runtime,
      configured_agent_id: resolve_configured_agent_id,
      tool_ids: resolve_tool_ids,
      skill_ids: resolve_skill_ids,
      mcp_server_ids: resolve_mcp_server_ids,
      repository_ids: resolve_repository_ids,
      input_asset_ids: resolve_input_asset_ids,
      mode: resolve_mode,
      bmad_enabled: resolve_bmad_enabled
    }
  end

  def resolve_with_breakdown
    {
      session_type: session_type,
      agent_runtime: resolve_agent_runtime,
      agent_runtime_source: resolve_agent_runtime_source,
      configured_agent_id: resolve_configured_agent_id,
      tools: build_resource_breakdown(:tool_ids),
      skills: build_resource_breakdown(:skill_ids),
      mcp_servers: build_resource_breakdown(:mcp_server_ids),
      input_assets: build_input_asset_breakdown,
      repositories: build_repository_breakdown,
      mode: resolve_mode,
      bmad_enabled: resolve_bmad_enabled
    }
  end

  def resolve_bmad_enabled
    if standalone_session?
      session.bmad_enabled?
    else
      step&.bmad_enabled || false
    end
  end

  private

  # --- Session navigation ---

  def user            = session.user
  # Per-company: credentials and the default runtime hang off the membership in
  # the session's company, never off the user (billing must not cross tenants).
  def membership      = (@membership ||= SessionCompany.membership_for(session))
  def credentials     = SessionCompany.agent_credentials_for(session)
  def project         = session.project
  def step_run        = session.step_run
  def workflow_run    = step_run&.workflow_run
  def workflow        = workflow_run&.workflow
  def step            = step_run&.step
  def board_task      = workflow_run&.board_task

  def workflow_session? = step_run.present?
  def board_triggered?  = workflow_session? && board_task.present?
  def standalone_session? = !workflow_session?

  def session_type
    if board_triggered?
      :board_triggered
    elsif workflow_session?
      :workflow
    else
      :standalone
    end
  end

  # --- Scalar resolution ---

  def resolve_agent_runtime
    return session.agent_type if standalone_session?

    step&.required_agent_runtime.presence ||
      workflow_run&.agent_runtime.presence ||
      membership&.default_agent_runtime ||
      credentials.order(created_at: :desc).first&.agent_type ||
      "claude_code"
  end

  def resolve_configured_agent_id
    return session.configured_agent_id if standalone_session?

    step&.agent_id
  end

  def resolve_mode
    return session.mode if standalone_session?

    auto = workflow_run.step_auto_run?(step.id)
    return "non_interactive" if auto == true
    return "non_interactive" if workflow_run.mode.non_interactive?
    return "non_interactive" if workflow_run.mode.mixed? && step.allow_non_interactive && auto != false

    "interactive"
  end

  # --- Set resolution (additive: project inherit_all + workflow base + step) ---

  def resolve_tool_ids
    return session.tool_ids if standalone_session?

    ids = []
    ids += project_tool_ids if workflow&.inherit_all_project_resources
    ids += workflow&.base_tool_ids || []
    ids += step&.tool_ids || []
    ids.uniq
  end

  def resolve_skill_ids
    return session.skill_ids if standalone_session?

    ids = []
    ids += project_skill_ids if workflow&.inherit_all_project_resources
    ids += workflow&.base_skill_ids || []
    ids += step&.skill_ids || []
    ids.uniq
  end

  def resolve_mcp_server_ids
    return session.mcp_server_ids if standalone_session?

    ids = []
    ids += project_mcp_server_ids if workflow&.inherit_all_project_resources
    ids += workflow&.base_mcp_server_ids || []
    ids += step&.mcp_server_ids || []
    ids.uniq
  end

  def resolve_repository_ids
    if workflow_session?
      workflow_session_repository_ids
    else
      session.repository_ids.presence || []
    end
  end

  def resolve_input_asset_ids
    if workflow_session?
      ids = []
      ids += workflow&.base_asset_ids || []
      ids += step&.asset_ids || []
      ids += workflow_run&.input_asset_ids || []
      ids += board_task_asset_ids
      ids.uniq
    else
      session.input_asset_ids
    end
  end

  # --- Helpers ---

  def project_tool_ids
    Tool.visible_for_project(project).pluck(:id)
  end

  def project_skill_ids
    Skill.visible_for_project(project).pluck(:id)
  end

  def project_mcp_server_ids
    MCPServer.visible_for_project(project).pluck(:id)
  end

  def project_repository_ids
    return [] unless project.present?

    Repository.visible_for_project(project).pluck(:id)
  end

  # --- Breakdown helpers for traceability ---

  def resolve_agent_runtime_source
    return "session_direct" if standalone_session?
    return "step_required" if step&.required_agent_runtime.present?
    return "run_override" if workflow_run&.agent_runtime.present?
    return "membership_default" if membership&.default_agent_credential.present?
    return "latest_credential" if credentials.exists?

    "fallback"
  end

  def build_resource_breakdown(resource_type)
    if standalone_session?
      ids = session.public_send(resource_type)
      return { from_session_direct: ids, resolved: ids }
    end

    project_method = :"project_#{resource_type}"
    from_project = workflow&.inherit_all_project_resources ? send(project_method) : []
    base_method = :"base_#{resource_type}"
    from_base = workflow&.public_send(base_method) || []
    from_step = step&.public_send(resource_type) || []
    resolved = (from_project + from_base + from_step).uniq

    {
      from_project_inherit_all: from_project,
      from_workflow_base: from_base,
      from_step: from_step,
      resolved: resolved
    }
  end

  def build_input_asset_breakdown
    if standalone_session?
      ids = session.input_asset_ids
      return { from_session_direct: ids, resolved: ids }
    end

    from_base = workflow&.base_asset_ids || []
    from_step = step&.asset_ids || []
    from_run = workflow_run&.input_asset_ids || []
    from_board = board_task_asset_ids
    resolved = (from_base + from_step + from_run + from_board).uniq

    {
      from_workflow_base: from_base,
      from_step: from_step,
      from_run_user: from_run,
      from_board_task: from_board,
      resolved: resolved
    }
  end

  def build_repository_breakdown
    if standalone_session?
      ids = session.repository_ids.presence || []
      return { from_session_direct: ids, resolved: ids }
    end

    from_run = workflow_run&.repository_ids || []
    from_base = workflow&.base_repository_ids || []
    from_step = step&.repository_ids || []
    explicit = (from_run + from_base + from_step).uniq
    from_project_fallback = explicit.any? || !workflow_inherits_project_resources? ? [] : project_repository_ids

    {
      from_run: from_run,
      from_workflow_base: from_base,
      from_step: from_step,
      from_project_fallback: from_project_fallback,
      resolved: explicit.presence || from_project_fallback
    }
  end

  # Repositories are chosen, not inherited-by-default: an explicit pick at ANY
  # level is the whole answer. Unlike tools and skills, which are additive, adding
  # the project's repositories on top of a deliberate choice would widen it — pick
  # one repository and get all four. `inherit_all_project_resources` therefore acts
  # as a fallback for workflows that chose nothing, not as another summand.
  #
  # Nothing here asks how the run was triggered. A step needs the same code whether
  # a person pressed Run, a board column moved, or a cron fired.
  def workflow_session_repository_ids
    explicit = explicit_repository_ids
    return explicit if explicit.any?
    return project_repository_ids if workflow_inherits_project_resources?

    []
  end

  def explicit_repository_ids
    ids = []
    ids += workflow_run&.repository_ids || []
    ids += workflow&.base_repository_ids || []
    ids += step&.repository_ids || []
    ids.uniq
  end

  def workflow_inherits_project_resources?
    workflow&.inherit_all_project_resources == true
  end

  def board_task_asset_ids
    return [] unless board_task.present?

    # TaskAsset is a Shrine-uploaded file, not a reference to Asset.
    # When asset_id is added to task_assets, use: board_task.task_assets.where.not(asset_id: nil).pluck(:asset_id)
    []
  end
end
