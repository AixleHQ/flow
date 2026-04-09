# frozen_string_literal: true

class Web::Company::Projects::MembersController < Web::Company::Projects::ApplicationController
  def index
    members = current_project.member_users

    render inertia: "Projects/Members/MembersPage", props: {
      project: project_props,
      members: members.map { |u| UserResource.new(u).to_h },
      company_users: current_company.users.order(:name).map { |u| UserResource.new(u).to_h },
      owner_id: current_project.owner_id
    }
  end

  def create
    user = current_company.users.find(collaborator_params[:user_id])
    collaborator = current_project.project_collaborators.new(user: user)

    if collaborator.save
      redirect_to company_project_members_path(current_project), notice: "#{user.name} added to project"
    else
      redirect_to company_project_members_path(current_project), inertia: { errors: collaborator.errors }
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

  def collaborator_params
    params.require(:collaborator).permit(:user_id)
  end
end
