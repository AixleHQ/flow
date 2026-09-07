# frozen_string_literal: true

module Web
  module Company
    module Projects
      class WorkflowRunsPolicy < Web::Company::ApplicationPolicy
        def index? = project_accessible?
        def show? = project_accessible?
        def create? = project_writable?
        def cancel? = controllable?
        def approve_step? = controllable?
        def retry_step? = controllable?
        def skip_step? = controllable?

        private

        # Steering a run is closed to everyone but its owner (and company
        # admins) — see WorkflowRun#controllable_by?. A run the params don't
        # name, or one this project doesn't own, is left to the controller's
        # own lookup to turn into a 404 rather than being masked as a denial.
        def controllable?
          return false unless project_writable?

          run = current_run
          run.nil? || run.controllable_by?(current_user)
        end

        def current_run
          return nil if context.params[:id].blank?

          @current_run ||= project&.workflow_runs&.find_by(id: context.params[:id])
        end
      end
    end
  end
end
