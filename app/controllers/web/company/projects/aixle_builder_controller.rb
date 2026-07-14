# frozen_string_literal: true

class Web::Company::Projects::AixleBuilderController < Web::Company::Projects::ApplicationController
  def show
    sessions = current_project.terminal_sessions
                       .with_cached_resource_counts
                       .includes(:user, :project, :tools, :skills, :mcp_servers,
                                 :input_assets, :repositories)
                       .where(user: current_user)
                       .where("metadata @> ?", { aixle_builder: true }.to_json)
                       .order(created_at: :desc)
                       .limit(20)

    active_session = sessions.find { |s| %w[not_started running ready].include?(s.state) }

    render inertia: "Projects/AixleBuilder/LandingPage", props: {
      sessions: -> { sessions.map { |s| TerminalSessionResource.new(s).to_h } },
      active_session_id: -> { active_session&.id },
      configured_agents: -> { current_user.configured_agents },
      assets: -> { Asset.accessible_from_project(current_project).map { |a| PickerResource.new(a).to_h } },
      agent_models: InertiaRails.defer { current_user.agent_models_for_props }
    }
  end

  def start
    meta_tool_ids = Tool.shadow_rows_for_names(
      Tools::Registry.tagged(:builder).map(&:name)
    ).select(&:enabled?).map(&:id)

    session = SessionService.create_and_start(
      user: current_user,
      project: current_project,
      session_type: "agent_session",
      agent_type: params[:agent_runtime] || current_user.default_agent_runtime || "claude_code",
      params: {
        mode: "interactive",
        initial_prompt: "First read the reference files in /workspace/references/ (aixle-system-reference.md and bmad-llms-full.txt) to understand the platform. Then help me build a workflow automation — start by asking what process I want to automate.",
        tool_ids: meta_tool_ids,
        requested_model: params[:preferred_model],
        metadata: { aixle_builder: true },
        input_asset_ids: Array(params[:input_asset_ids]).map(&:to_i),
        session_config: {
          "bmad_enabled" => true,
          "config_files" => builder_reference_files
        }
      }
    )

    unless session.persisted?
      redirect_to company_project_aixle_builder_path(current_project), alert: session.errors.full_messages.to_sentence.presence || "Failed to create session"
      return
    end

    redirect_to company_project_aixle_builder_session_path(current_project, session)
  end

  def show_session
    ts = current_project.terminal_sessions
                 .where(user: current_user)
                 .where("metadata @> ?", { aixle_builder: true }.to_json)
                 .find_by(id: params[:id])
    return head :not_found unless ts

    render inertia: "Projects/AixleBuilder/SessionPage", props: {
      session: -> { TerminalSessionResource.new(ts).to_h },
      cable_stream: -> { inertia_cable_stream(ts) },
      builder_activities: InertiaRails.defer {
        ts.reload
        activities = ts.metadata&.dig("builder_activities") || []
        Rails.logger.info("[AixleBuilder] builder_activities count=#{activities.size} for session=#{ts.id}")
        activities.last(100).reverse.map do |a|
          a.transform_keys { |k| k.to_s.camelize(:lower) }
        end
      },
      workflows: InertiaRails.defer {
        Workflow.visible_for_project(current_project)
                .includes(:steps, :runs)
                .order(:name)
                .map { |w| WorkflowResource.new(w).to_h }
      },
      board_columns: InertiaRails.defer {
        board = current_project.board
        if board
          board.board_columns
               .includes(column_workflow_binding: :workflow)
               .order(:position)
               .map { |c| BoardColumnResource.new(c).to_h }
        else
          []
        end
      }
    }
  end

  def finish
    ts = current_project.terminal_sessions
                 .where(user: current_user)
                 .where("metadata @> ?", { aixle_builder: true }.to_json)
                 .find_by(id: params[:id])
    return head :not_found unless ts

    SessionService.finish(session: ts)
    redirect_to company_project_aixle_builder_session_path(current_project, ts)
  rescue TerminalSession::InvalidStateError => e
    redirect_to company_project_aixle_builder_session_path(current_project, ts), alert: e.message
  end

  private

  def builder_reference_files
    files = {}
    ref_dir = Rails.root.join("references")
    if ref_dir.exist?
      ref_dir.children.select(&:file?).each do |path|
        files["/workspace/references/#{path.basename}"] = File.read(path)
      end
    end
    files
  end
end
