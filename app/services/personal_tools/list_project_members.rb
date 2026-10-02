# frozen_string_literal: true

module PersonalTools
  class ListProjectMembers < Base
    tool do
      display_name "List Project Members"
      description "List the users who can access a project, with ids to use as a board task assignee."
      audience :user
      tags :resources
      read_only
      param :project_id, type: :integer, description: "Project id (from list_projects).", required: true
    end

    def execute
      project = find_project!
      authorize!(project, :index?, policy: Web::Company::Projects::MembersPolicy, project: project)

      members = project.assignable_users.map do |u|
        { id: u.id, name: u.name, email: u.email, role: u.id == project.owner_id ? "owner" : "collaborator" }
      end
      success(project_id: project.id, members: members)
    end
  end
end
