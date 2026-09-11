# frozen_string_literal: true

# The organization-visible member profile at `/user/:id`.
#
# Read-only and company-scoped: any signed-in member of the current company can
# open it for any other member of that company, and nobody else can reach it at
# all. An unknown id — or one belonging to someone in another company — is a
# 404 rather than a 403, so the page never confirms that an account exists
# outside the viewer's company.
#
# It exists to answer one question the owner's own Profile cannot answer for
# anybody else: is this person's connected CLI subscription spent? That is why
# the Usage limits card is built from the SUBJECT's membership and credentials,
# not the viewer's — and why the fetch is deferred and throttled per credential
# (Agents::SubscriptionUsageService), so a room full of teammates opening the
# page cannot turn into a vendor 429 for the owner.
#
# What is deliberately NOT here: credentials, the AWS connection, the MCP
# token, the session-sharing switches, "leave company". Those stay on the
# owner's own Profile — this page is a read, not a second account screen.
class Web::Company::UsersController < Web::Company::ApplicationController
  def show
    membership = member_membership

    scope = member_sessions_scope
              .with_cached_resource_counts
              .includes(:user, :project, :session_admission,
                        :tools, :skills, :mcp_servers, :config_items,
                        :input_assets, :repositories)
              .order(created_at: :desc)

    render inertia: "Company/Users/Show", props: {
      member: MemberResource.new(membership).to_h,
      viewer_is_self: membership.user_id == current_user.id,
      total: member_sessions_scope.count,
      # Where a row may be opened FROM THIS PAGE. The company-wide session page
      # is admin-only, and a project's session page needs access to that
      # project, so a plain member has no route to a colleague's session in a
      # project they are not on. Saying so up front beats rendering a link that
      # only bounces them back with "not authorized".
      viewer_is_admin: current_membership&.admin? || false,
      accessible_project_ids: accessible_project_ids,
      # Opening a row still goes through TerminalSession#visible_to?: passing
      # the viewer redacts the prompt and metadata of sessions the owner keeps
      # private, and the row renders as a lock instead of disappearing.
      sessions: inertia_scroll(scope) { |records|
        records.map { |s| TerminalSessionResource.new(s, params: { viewer: current_user }).to_h }
      },
      # Fetched over HTTP from the runtime vendor, so deferred exactly as on the
      # owner's own Profile: a slow or dead provider must not blank the sessions
      # list. `?refresh=1` is the Refresh button, throttled by the service.
      usage_limits: InertiaRails.defer(group: "limits") {
        Agents::SubscriptionUsageService.new(membership: membership, force: params[:refresh].present?).call
      },
      period: period,
      **analytics_props(membership.user)
    }
  end

  private

  # The subject, resolved through THIS company only — the scoping that makes the
  # page company-private. Revoked memberships and soft-deleted accounts are gone
  # from the product, so they 404 here too; every other state the Members list
  # shows (invited, active, suspended) is a member and has a page, or the links
  # from that list would be dead.
  def member_membership
    @member_membership ||= current_company.company_memberships
                                          .where.not(state: "revoked")
                                          .joins(:user).where(users: { deleted_at: nil })
                                          .find_by!(user_id: params[:id])
  end

  # Aixle spend for this person in this company — the same four panels, the same
  # services and the same deferral group as Profile -> Usage. Nothing new is
  # exposed: /profile/usage?user_id= already answers this for any member of the
  # company (see ProfileController#resolve_target_user); this only puts the
  # answer on the page people actually open to ask it.
  def analytics_props(target)
    company = current_company

    {
      summary: InertiaRails.defer(group: "usage") {
        r = UserAnalyticsService.new(user: target, company:, period:, project_id: nil).call
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
        r = UserAgentActivityService.new(user: target, company:, period:, project_id: nil).call
        { sessionsByAgent: r.sessions_by_agent.map { |a| { agentType: a.agent_type, sessions: a.sessions, costCents: a.cost_cents, tokens: a.tokens } } }
      },
      cost_token: InertiaRails.defer(group: "usage") {
        r = UserSessionCostTokenUsageService.new(user: target, company:, period:, project_id: nil).call
        { timeSeries: r.time_series.map { |p| { date: p.date, costCents: p.cost_cents, totalTokens: p.total_tokens } } }
      },
      activity_heatmap: InertiaRails.defer(group: "usage") {
        scope = target.terminal_sessions.joins(:project).where(projects: { company_id: company.id })
        { days: ActivityHeatmapService.new(scope:).call.map { |d| { date: d.date, count: d.count } } }
      }
    }
  end

  # The window the charts cover. An unknown value would reach the services as a
  # period they cannot answer, so only the four the picker offers are accepted.
  PERIODS = %w[7d 30d 90d 1y].freeze

  def period
    @period ||= PERIODS.include?(params[:period]) ? params[:period] : "30d"
  end

  # The current company's projects this viewer may open a session in — the same
  # rule Project#accessible_by? applies one record at a time (owner,
  # collaborator, or company admin), asked once for the whole list.
  def accessible_project_ids
    Project.for_user(current_user).for_company(current_company).pluck(:id)
  end

  # This person's slice of the company-wide Sessions & Runs feed: the same
  # session-level vocabulary and the same company scoping, filtered to one
  # owner. A dual-membership user's work in another company never appears,
  # because company_sessions_scope is already bounded by the current company.
  def member_sessions_scope
    @member_sessions_scope ||= company_sessions_scope.where(
      user_id: member_membership.user_id,
      session_type: SessionsRunsFeed::LISTABLE_SESSION_TYPES
    )
  end
end
