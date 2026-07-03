# frozen_string_literal: true

module PersonalTools
  class CreateProject < Base
    tool do
      display_name "Create Project"
      description "Create a new project in your company, owned by you."
      audience :user
      tags :account
      param :name, type: :string, description: "Project name.", required: true
      param :description, type: :string, description: "Project description."
    end

    def execute
      return error("You are not part of a company") if user.company.nil?

      authorize!(nil, :create?, policy: Web::Company::ProjectsPolicy)
      project = user.company.projects.create!(name: params[:name], description: params[:description], owner: user)
      success(id: project.id, name: project.name, slug: project.slug)
    rescue ActiveRecord::RecordInvalid => e
      error("Failed to create project: #{e.message}")
    end
  end
end
