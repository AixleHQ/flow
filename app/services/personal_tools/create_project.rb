# frozen_string_literal: true

module PersonalTools
  class CreateProject < Base
    tool do
      display_name "Create Project"
      description "Create a new project in one of your companies, owned by you."
      audience :user
      tags :account
      param :name, type: :string, description: "Project name.", required: true
      param :description, type: :string, description: "Project description."
      param :company_id, type: :integer,
                         description: "Company to create the project in (see list_companies). Required when you belong to more than one company."
    end

    def execute
      company = resolve_company!

      authorize!(nil, :create?, policy: Web::Company::ProjectsPolicy, company: company)
      project = company.projects.create!(name: params[:name], description: params[:description], owner: user)
      success(id: project.id, name: project.name, slug: project.slug)
    rescue ActiveRecord::RecordInvalid => e
      error("Failed to create project: #{e.message}")
    end
  end
end
