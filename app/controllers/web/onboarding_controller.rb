# frozen_string_literal: true

class Web::OnboardingController < Web::ApplicationController
  layout "inertia"

  skip_before_action :enforce_onboarding
  before_action :require_auth

  def show
    if current_user.onboarding_state == "completed"
      redirect_to company_projects_path
      return
    end

    active_auth_sessions = current_user.terminal_sessions.auth_sessions.active

    render inertia: "Onboarding/OnboardingPage", props: {
      auth_sessions: active_auth_sessions.map { |s| TerminalSessionResource.new(s).to_h },
      cable_stream: inertia_cable_stream(current_user)
    }
  end

  def update
    if current_user.update(onboarding_params)
      redirect_to onboarding_path
    else
      redirect_to onboarding_path, alert: current_user.errors.full_messages.join(", ")
    end
  end

  private

  def require_auth
    redirect_to login_path unless signed_in?
  end

  def onboarding_params
    params.require(:onboarding).permit(
      :position, :preferred_agent_language,
      :onboarding_state_event,
      selected_agents: []
    )
  end
end
