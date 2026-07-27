# frozen_string_literal: true

class Web::OnboardingController < Web::ApplicationController
  layout "inertia"

  # go_previous is required — the onboarding UI's Back button submits it
  # (OnboardingPage.tsx). Omitting it silently no-ops the Back button.
  ALLOWED_ONBOARDING_EVENTS = %w[go_next go_previous complete].freeze

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

    render inertia: "Onboarding/OnboardingPage", props: {
      auth_sessions: active_auth_sessions.map { |s| TerminalSessionResource.new(s).to_h },
      cable_stream: inertia_cable_stream(current_user)
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
end
