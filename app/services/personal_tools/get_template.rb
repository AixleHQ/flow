# frozen_string_literal: true

module PersonalTools
  class GetTemplate < Base
    tool do
      display_name "Get Template"
      description "Read a catalog template in full: what it creates, the inputs it asks for, and what it " \
                  "leaves to set up afterwards (secrets, integrations, repositories). Pass its version and " \
                  "commit_sha to install_template so the install refuses if the template changed meanwhile."
      audience :user
      tags :templates
      read_only
      param :slug, type: :string, description: "Template slug (see search_template_catalog).", required: true
    end

    def execute
      template = CatalogTemplate.find_by(slug: params[:slug].to_s)
      return error("Template '#{params[:slug]}' is not in the catalog") unless template

      success(Templates::Presenter.detail(template))
    end
  end
end
