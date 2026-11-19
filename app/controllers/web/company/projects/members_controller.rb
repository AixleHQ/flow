# frozen_string_literal: true

class Web::Company::Projects::MembersController < Web::Company::Projects::ApplicationController
  def index
    members = current_project.member_users.includes(:company_memberships)

    render inertia: "Projects/Members/MembersPage", props: {
      project: project_props,
      members: members.map { |u| UserResource.new(u, params: { company: current_company }).to_h },
      company_users: addable_users.includes(:company_memberships).order(:name)
                                  .map { |u| UserResource.new(u, params: { company: current_company }).to_h },
      owner_id: current_project.owner_id,
      ownership: ownership_props
    }
  end

  def create
    users = addable_users.find(collaborator_user_ids)
    collaborators = users.map { |user| current_project.project_collaborators.new(user: user) }

    if ProjectCollaborator.transaction { collaborators.all?(&:save) || raise(ActiveRecord::Rollback) }
      redirect_to company_project_members_path(current_project), notice: added_notice(users)
    else
      failed = collaborators.find { |collaborator| collaborator.errors.any? }
      redirect_to company_project_members_path(current_project), inertia: { errors: failed.errors }
    end
  end

  def destroy
    if params[:id].to_i == current_user.id
      redirect_to company_project_members_path(current_project), alert: "Cannot remove yourself from the project"
      return
    end

    current_project.project_collaborators.find_by!(user_id: params[:id]).destroy
    redirect_to company_project_members_path(current_project), notice: "Collaborator removed from project"
  end

  private

  # Company members, and people whose invitation is still open: they can be put
  # on the project now and reach it once they accept.
  def addable_users
    User.for_company(current_company).merge(CompanyMembership.active_or_invited)
  end

  def collaborator_user_ids
    collaborator = params.require(:collaborator).permit(:user_id, user_ids: [])
    # A tab opened before the multi-select still posts a single user_id.
    ids = collaborator[:user_ids].presence || Array(collaborator[:user_id].presence)
    ids.presence || raise(ActionController::ParameterMissing, :user_ids)
  end

  def added_notice(users)
    return "#{users.first.name} added to project" if users.one?

    "#{users.size} members added to project"
  end
end
