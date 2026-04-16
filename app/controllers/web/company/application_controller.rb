# frozen_string_literal: true

class Web::Company::ApplicationController < Web::ApplicationController
  include Pundit::Authorization
  include AuthorizationConcern

  layout "inertia"

  before_action :require_auth
  before_action :dynamic_authorize!

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  inertia_share do
    {
      permissions: InertiaRails.always {
        {
          is_admin: current_user.admin?,
          can_manage_members: current_user.admin?,
          can_manage_projects: current_user.admin?
        }
      }
    }
  end

  private

  def policy_context
    BaseContext.new(current_user, params)
  end

  def user_not_authorized
    redirect_back fallback_location: root_path, alert: "You are not authorized to perform this action."
  end

  def current_company
    @current_company ||= current_user.company
  end

  def require_auth
    redirect_to login_path unless signed_in?
  end

  def require_admin
    head :forbidden unless current_user.admin?
  end

  def company_sessions_scope
    TerminalSession.left_joins(:project)
                   .where("terminal_sessions.user_id IN (?) OR projects.company_id = ?",
                          current_company.users.select(:id), current_company.id)
  end
end
