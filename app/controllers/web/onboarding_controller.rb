# frozen_string_literal: true

class Web::OnboardingController < Web::ApplicationController
  layout "inertia"

  # go_previous is required — the onboarding UI's Back button submits it
  # (OnboardingPage.tsx). Omitting it silently no-ops the Back button.
  ALLOWED_ONBOARDING_EVENTS = %w[go_next go_previous complete viewer_advance].freeze

  skip_before_action :enforce_onboarding
  before_action :require_auth
  before_action :require_membership

  # Onboarding runs against the CURRENT MEMBERSHIP, not the user: each company
  # gets its own role, agent selection and agent credential.
  def show
    if current_membership.onboarding_completed?
      redirect_to company_projects_path
      return
    end

    # Auth sessions for THIS company only — an auth_setup session in another
    # company is authenticating that company's separately-billed credential.
    active_auth_sessions = current_user.terminal_sessions
                                       .auth_sessions
                                       .active
                                       .where(company_id: current_membership.company_id)

    viewer_preview = build_viewer_workflow_preview(current_user.company) if current_user.viewer?

    render inertia: "Onboarding/OnboardingPage", props: {
      auth_sessions: -> { active_auth_sessions.map { |s| TerminalSessionResource.new(s).to_h } },
      cable_stream: -> { inertia_cable_stream(current_user) },
      viewer_workflow_preview: -> { viewer_preview }
    }
  end

  def update
    # with_lock prevents concurrent requests from double-advancing the onboarding state
    current_membership.with_lock do
      if current_membership.update(onboarding_params)
        redirect_to onboarding_path
      else
        redirect_to onboarding_path, alert: current_membership.errors.full_messages.join(", ")
      end
    end
  end

  private

  def require_auth
    redirect_to login_path unless signed_in?
  end

  # A super admin has no membership and no onboarding; anyone else without one
  # has nothing to onboard into.
  def require_membership
    return if current_membership

    redirect_to current_user&.super_admin? ? admin_root_path : login_path
  end

  def onboarding_params
    permitted = params.require(:onboarding).permit(
      :position, :preferred_agent_language,
      selected_agents: []
    )
    # Only allow forward-direction events to prevent state reversal via rapid transitions
    event = params.dig(:onboarding, :onboarding_state_event)
    permitted[:onboarding_state_event] = event if event.present? && ALLOWED_ONBOARDING_EVENTS.include?(event)
    permitted
  end

  def build_viewer_workflow_preview(company)
    return nil if company.nil?

    workflow = company.projects.flat_map(&:workflows).first
    return nil if workflow.nil?

    steps_assoc = workflow.respond_to?(:steps) ? workflow.steps : []
    limited_steps = steps_assoc.respond_to?(:limit) ? steps_assoc.limit(4) : steps_assoc.first(4)

    {
      workflow_name: workflow.name,
      workflow_description: workflow.description.presence || "An automated workflow",
      steps: limited_steps.map { |s| { name: s.name, description: s.description } }
    }
  rescue => e
    Rails.logger.warn("viewer workflow preview failed: #{e.message}")
    nil
  end
end
