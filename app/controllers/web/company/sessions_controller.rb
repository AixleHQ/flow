# frozen_string_literal: true

class Web::Company::SessionsController < Web::Company::ApplicationController
  def index
    scope = company_sessions_scope.with_cached_resource_counts
              .includes(:user, :project,
                        :tools, :skills, :mcp_servers, :config_items,
                        :input_assets, :repositories)
              .where.not(session_type: "auth_setup")
              .ransack(q_params)
              .result
              .order(created_at: :desc)

    render inertia: "Company/Sessions/Index", props: {
      sessions: inertia_scroll(scope) { |records|
        records.map { |s| TerminalSessionResource.new(s, params: { viewer: current_user }).to_h }
      },
      filters: q_params,
      per_page: per_page
    }
  end

  def show
    session = company_sessions_scope.with_cached_resource_counts
                .includes(:user, :project,
                          :tools, :skills, :mcp_servers, :config_items,
                          :input_assets, :repositories)
                .find(params[:id])
    authorize_session_visibility!(session)

    session_props = TerminalSessionResource.new(session, params: { viewer: current_user }).to_h

    render inertia: "Company/Sessions/Show", props: {
      session: session_props,
      cable_stream: inertia_cable_stream(session)
    }
  end
end
