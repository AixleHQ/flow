# frozen_string_literal: true

module Admin
  # Moves a project into another company (ProjectMove). Not an Administrate
  # resource: a preflight page, the move, and the report it leaves behind.
  class ProjectMovesController < Admin::ApplicationController
    before_action :set_project

    def new
      @companies = Company.where.not(id: @project.company_id).order(:name)
      @target = @companies.find_by(id: params[:target_company_id])
      @preflight = ProjectMove::Preflight.new(project: @project, target: @target) if @target

      render layout: "administrate/application"
    end

    def create
      target = Company.find(params.require(:target_company_id))
      ProjectMove::Mover.new(
        project: @project, target: target, owner: User.find_by(id: params[:owner_id]),
        member_policy: params[:member_policy], confirm_cancellations: params[:confirm_cancellations],
        actor: true_user, request: request
      ).call

      redirect_to admin_project_move_path(@project), notice: "#{@project.reload.name} moved to #{target.name}."
    rescue ProjectMove::Refused => e
      redirect_to new_admin_project_move_path(@project, target_company_id: target&.id), alert: e.message
    end

    def show
      @audit = Audit.where(associated: @project, action: "project_moved_in").order(:id).last
      return redirect_to(admin_project_path(@project), alert: "#{@project.name} has not been moved.") if @audit.nil?

      @report = @audit.audited_changes
      render layout: "administrate/application"
    end

    private

    def set_project
      @project = Project.find(params[:project_id])
    end
  end
end
