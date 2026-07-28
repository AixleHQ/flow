# frozen_string_literal: true

class Web::ProfileController < Web::ApplicationController
  layout "inertia"

  before_action :require_auth

  def show
    render inertia: "Profile/Show", props: {
      profile: CurrentUserResource.new(current_user, params: { current_membership: current_membership }).to_h,
      # Invitations the user has NOT accepted yet. `profile.memberships` is
      # active-only, so without this an outstanding invitation is visible
      # nowhere in the product — only in the email, which may be lost.
      # Profile-only (not a shared prop): pointless weight on every request.
      pending_invitations: current_user.company_memberships
                                       .invited
                                       .includes(:company)
                                       .map { |m| MembershipResource.new(m).to_h },
      language_options: CompanyMembership::AGENT_LANGUAGES,
      agent_models: current_membership&.agent_models_for_props || [],
      cable_stream: inertia_cable_stream(current_user),
      mcp: {
        enabled: current_user.mcp_enabled?,
        last_used_at: current_user.mcp_token_last_used_at,
        server_url: Settings.mcp.public_server_url,
        # Present only right after regeneration — shown once, never persisted.
        token: session.delete(:mcp_token_plaintext)
      }
    }
  end

  # Enable / rotate in one action: the previous token stops working the
  # moment a new digest lands.
  def regenerate_mcp_token
    session[:mcp_token_plaintext] = current_user.regenerate_mcp_token!
    redirect_to profile_path, notice: "MCP token generated — copy it now, it won't be shown again"
  end

  def disable_mcp_token
    current_user.disable_mcp_token!
    redirect_to profile_path, notice: "MCP access disabled"
  end

  def usage
    # Usage is ALWAYS a current-company slice — a dual-membership user's other
    # companies' sessions/costs must never surface here.
    company = current_company or raise ActiveRecord::RecordNotFound
    target     = resolve_target_user
    period     = params.fetch(:period, "30d")
    project_id = params[:project_id].presence

    render inertia: "Profile/Usage", props: {
      period:,
      project_id:,
      viewer_is_self: target.id == current_user.id,
      target_user: { id: target.id, name: target.name, email: target.email },
      summary: InertiaRails.defer(group: "usage") {
        r = UserAnalyticsService.new(user: target, company:, period:, project_id:).call
        {
          totalSessions: r.total_sessions,
          totalCostCents: r.total_cost_cents,
          totalTokens: r.total_tokens,
          avgCostCentsPerSession: r.avg_cost_cents_per_session,
          workflowsRun: r.workflows_run,
          projectBreakdowns: r.project_breakdowns.map { |p|
            { projectId: p.project_id, projectName: p.project_name, sessions: p.sessions, costCents: p.cost_cents, tokens: p.tokens }
          }
        }
      },
      agent_activity: InertiaRails.defer(group: "usage") {
        r = UserAgentActivityService.new(user: target, company:, period:, project_id:).call
        { sessionsByAgent: r.sessions_by_agent.map { |a| { agentType: a.agent_type, sessions: a.sessions, costCents: a.cost_cents, tokens: a.tokens } } }
      },
      cost_token: InertiaRails.defer(group: "usage") {
        r = UserSessionCostTokenUsageService.new(user: target, company:, period:, project_id:).call
        { timeSeries: r.time_series.map { |p| { date: p.date, costCents: p.cost_cents, totalTokens: p.total_tokens } } }
      },
      activity_heatmap: InertiaRails.defer(group: "usage") {
        scope = target.terminal_sessions.joins(:project).where(projects: { company_id: company.id })
        scope = scope.where(project_id:) if project_id
        { days: ActivityHeatmapService.new(scope:).call.map { |d| { date: d.date, count: d.count } } }
      },
      sessions: InertiaRails.defer(group: "usage") {
        target.terminal_sessions
              .joins(:project).where(projects: { company_id: company.id })
              .with_cached_resource_counts
              .includes(:user, :project, :tools, :skills, :mcp_servers, :input_assets, :repositories)
              .where.not(session_type: "auth_setup")
              .order(created_at: :desc)
              .limit(per_page)
              .map { |s| TerminalSessionResource.new(s).to_h }
      }
    }
  end

  # The profile form edits two records now: the name is global (User), while the
  # agent language is a per-company onboarding answer and lives on the CURRENT
  # membership. Permitting only :name here silently dropped language changes.
  def update
    user_ok = current_user.update(profile_params)
    membership_ok = update_current_membership_profile

    if user_ok && membership_ok
      redirect_to profile_path, notice: "Profile updated successfully"
    else
      errors = current_user.errors.any? ? current_user.errors : current_membership&.errors
      redirect_to profile_path, inertia: { errors: errors }
    end
  end

  def update_default_model
    credential = current_user.agent_credentials.find(params[:agent_credential_id])
    meta = credential.metadata || {}
    if params[:default_model].present?
      meta["default_model"] = params[:default_model]
    else
      meta.delete("default_model")
    end
    credential.update!(metadata: meta)

    redirect_to profile_path, notice: "Default model updated"
  end

  def destroy_credential
    credential = current_user.agent_credentials.find(params[:agent_credential_id])
    credential.destroy!

    redirect_to profile_path, notice: "#{credential.agent_type.titleize} credentials removed"
  end

  private

  def require_auth
    redirect_to login_path unless signed_in?
  end

  # Same-company scope guard (NOT admin-gated): the target must have an ACTIVE
  # membership in the CURRENT company. Foreign / unknown user_id → 404.
  # user_id absent → current_user (self-view).
  def resolve_target_user
    return current_user if params[:user_id].blank?

    raise ActiveRecord::RecordNotFound unless current_company

    current_company.users.merge(CompanyMembership.active).find(params[:user_id])
  end

  def profile_params
    params.require(:profile).permit(:name)
  end

  # Per-company answers editable from the profile. Super admins have no
  # membership, so there is nothing to write.
  def membership_profile_params
    params.require(:profile).permit(:preferred_agent_language, :default_agent_credential_id)
  end

  def update_current_membership_profile
    return true if current_membership.nil?

    attrs = membership_profile_params
    return true if attrs.empty?

    current_membership.update(attrs)
  end
end
