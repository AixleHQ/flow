# frozen_string_literal: true

module PersonalTools
  class ListProjects < Base
    tool do
      display_name "List Projects"
      description "List the projects you can access in every company you belong to, each with its " \
                  "`company_id` and the ids to use in other tools."
      audience :user
      tags :account
      read_only
      input_schema(type: "object", properties: {}, required: [])
    end

    def execute
      projects = accessible_projects.map do |project|
        { id: project.id, company_id: project.company_id, name: project.name, slug: project.slug,
          description: project.description, state: project.state }
      end
      success(projects: projects)
    end
  end
end
