# frozen_string_literal: true

# The install page (design §7.2): choose where the template goes, answer its
# inputs, resolve conflicts, then install. `new` renders the plan; `create`
# re-plans and installs only if the plan is still the one the user confirmed.
class Web::Company::TemplateInstallsController < Web::Company::ApplicationController
  skip_before_action :require_auth
  prepend_before_action :require_auth_remembering_template

  def new
    template = find_template
    installer = build_installer(template, idempotency_key: SecureRandom.uuid)
    render inertia: "Templates/InstallPage", props: page_props(template, installer)
  end

  def create
    template = find_template
    installer = build_installer(template, idempotency_key: params.require(:idempotency_key),
                                          secrets: params[:secrets], confirmed_digest: params[:digest])
    result = installer.apply
    redirect_to company_project_template_install_path(result.project, result.install),
                notice: result.created ? "#{template.name} is installed. Finish the setup below." : nil
  rescue Templates::Planner::Error => e
    redirect_to new_company_template_install_path(retry_params(template)), alert: e.message
  rescue ActiveRecord::RecordInvalid => e
    redirect_to new_company_template_install_path(retry_params(template)),
                alert: "Install failed: #{e.record.errors.full_messages.to_sentence}"
  end

  private

  # Keyed by template data — secret names are UPPER_CASE, resolution refs are
  # "agents.<key>" — so they must reach the installer verbatim, not underscored.
  def preserved_param_paths
    [ [ :secrets ], [ :inputs ], [ :resolutions ] ]
  end

  # A guest who pressed Install signs in and comes back to this template at the
  # version they saw; nothing else from the request is kept.
  def require_auth_remembering_template
    return if signed_in?

    remember_pending_template_install(slug: params[:slug], version: params[:version]) if params[:slug].present?
    redirect_to login_path
  end

  def find_template = CatalogTemplate.find_by!(slug: params[:slug])

  def build_installer(template, idempotency_key:, secrets: nil, confirmed_digest: nil)
    Templates::Installer.new(
      catalog_template: template, user: current_user, target: target(template), idempotency_key: idempotency_key,
      inputs: hash_param(:inputs), secrets: hash_param(:secrets, secrets), resolutions: hash_param(:resolutions),
      expected: { version: params[:version].presence }.compact, confirmed_digest: confirmed_digest.presence
    )
  end

  def target(template)
    if params[:project_id].present? && template.kind != "project"
      { project: writable_projects.find(params[:project_id]) }
    else
      { company: current_company, project_name: params[:project_name] }
    end
  end

  def writable_projects
    Project.for_user(current_user).for_company(current_company).with_state(:active).order(:name)
  end

  def hash_param(key, value = params[key])
    return {} unless value.respond_to?(:to_unsafe_h) || value.is_a?(Hash)

    (value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h : value).to_h.transform_values(&:to_s)
  end

  def page_props(template, installer)
    plan = installer.plan
    base_props(template, installer).merge(plan: Templates::Presenter.plan(plan), error: nil)
  rescue Templates::Planner::Error => e
    base_props(template, installer).merge(plan: nil, error: e.message)
  end

  def base_props(template, installer)
    {
      template: Templates::Presenter.detail(template),
      idempotency_key: installer.idempotency_key,
      company_name: current_company.name,
      projects: template.kind == "project" ? [] : writable_projects.map { |p| { id: p.id, name: p.name } },
      # Keyed by template data (input keys, "agents.<key>"), so sent as pairs:
      # Inertia camelizes every hash key it ships, which would mangle them.
      selection: { project_id: params[:project_id].presence&.to_i, project_name: params[:project_name],
                   inputs: pairs(hash_param(:inputs)), resolutions: pairs(hash_param(:resolutions)) }
    }
  end

  def pairs(hash) = hash.map { |key, value| { key: key, value: value } }

  def retry_params(template)
    { slug: template&.slug || params[:slug], project_id: params[:project_id].presence,
      project_name: params[:project_name].presence, inputs: hash_param(:inputs).presence,
      resolutions: hash_param(:resolutions).presence }.compact
  end
end
