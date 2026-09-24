# frozen_string_literal: true

module PersonalTools
  # The install page's path, over MCP. A whole-project template always creates
  # a new project; any other kind can go into an existing project, where a
  # same-named resource with different content is a conflict the caller must
  # resolve before anything is written.
  class InstallTemplate < Base
    tool do
      display_name "Install Template"
      description "Install a catalog template. Give company_id (and optionally project_name) to create a new " \
                  "project, or project_id to add a non-project template to an existing one. Call with " \
                  "dry_run first: it returns the plan, including conflicts with same-named resources, which " \
                  "you resolve through `resolutions` (\"agents.<key>\": \"use_existing\" | \"copy\"). " \
                  "Every trigger is installed inactive; the result names the checklist page where the user " \
                  "activates them and adds what is still missing. Third-party containers and prompt text " \
                  "come with the template — confirm with the user before installing."
      audience :user
      tags :templates
      param :slug, type: :string, description: "Template slug.", required: true
      param :version, type: :integer, description: "Version read with get_template; refused if it changed."
      param :commit_sha, type: :string, description: "commit_sha read with get_template; refused if it changed."
      param :company_id, type: :integer, description: "Company to create a new project in."
      param :project_id, type: :integer, description: "Existing project to install into (not for project templates)."
      param :project_name, type: :string, description: "Name for the new project. Defaults to the template name."
      param :inputs, type: :object, description: "Answers to the template's inputs, keyed by input key."
      param :secrets, type: :object,
                      description: "Secret values to store now, keyed by secret name. Write-only: never returned. " \
                                   "Leave out to have the user add them on the checklist page."
      param :resolutions, type: :object, description: "Conflict decisions from the dry run's plan."
      param :idempotency_key, type: :string,
                              description: "Any unique string for this install; repeating a call with the same key " \
                                           "returns the first install instead of creating another.",
                              required: true
      param :dry_run, type: :boolean, description: "Return the plan without installing."
    end

    def execute
      template = CatalogTemplate.find_by(slug: params[:slug].to_s)
      return error("Template '#{params[:slug]}' is not in the catalog") unless template

      installer = Templates::Installer.new(
        catalog_template: template, user: user, target: target, idempotency_key: params[:idempotency_key],
        inputs: hash_param(:inputs), secrets: hash_param(:secrets), resolutions: hash_param(:resolutions),
        expected: { version: params[:version], commit_sha: params[:commit_sha] }.compact
      )
      plan = installer.plan
      return success(installed: false, plan: Templates::Presenter.plan(plan)) if params[:dry_run] || !plan.resolved?

      result = installer.apply
      success(installed: true, created: result.created, project_id: result.project.id,
              project_name: result.project.name, template_install_id: result.install.id,
              checklist: result.install.setup_items.map { |item| Templates::Presenter.setup_item(item) },
              checklist_url: checklist_url(result))
    rescue Templates::Planner::Error => e
      error(e.message)
    rescue ActiveRecord::RecordInvalid => e
      error("Install failed: #{e.record.errors.full_messages.to_sentence}")
    end

    private

    def target
      if params[:project_id].present?
        { project: find_project! }
      else
        { company: resolve_company!, project_name: params[:project_name] }
      end
    end

    def hash_param(key)
      value = params[key]
      value.is_a?(Hash) ? value.to_h.transform_values { |v| v.is_a?(Hash) ? v : v.to_s } : {}
    end

    def checklist_url(result)
      Rails.application.routes.url_helpers.company_project_template_install_url(
        result.project, result.install, host: Settings.domain, protocol: Settings.protocol
      )
    end
  end
end
