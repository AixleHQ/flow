# frozen_string_literal: true

# A template install's checklist (design §7.5): what is left to connect, add or
# activate. Items that were completed elsewhere resolve on every render.
class Web::Company::Projects::TemplateInstallsController < Web::Company::Projects::ApplicationController
  def show
    install = current_project.template_installs.find(params[:id])
    Templates::SetupChecklist.new(install, user: current_user).refresh!
    template = install.catalog_template

    render inertia: "Projects/TemplateInstalls/ShowPage", props: {
      install: { id: install.id, slug: install.slug, version: install.version, installed_at: install.created_at,
                 name: template&.name || install.slug, setup: template&.setup_markdown },
      items: install.setup_items.map { |item| Templates::Presenter.setup_item(item) },
      repositories: current_project.repositories.order(:full_name).map { |r| { id: r.id, full_name: r.full_name } },
      integrations_path: company_project_integrations_path(current_project),
      mcp_servers_path: company_project_mcp_servers_path(current_project)
    }
  end
end
