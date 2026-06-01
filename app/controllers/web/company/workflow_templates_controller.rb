# frozen_string_literal: true

class Web::Company::WorkflowTemplatesController < Web::Company::ApplicationController
  include Web::Company::WorkflowTemplateSourceLookup

  def index
    templates = WorkflowTemplate.visible_to(current_user, current_company)
                                .includes(:owner, current_version: { workflow: :steps })
                                .select(
                                  "workflow_templates.*",
                                  "(SELECT COUNT(*) FROM projects WHERE projects.workflow_template_version_id IN " \
                                  "(SELECT id FROM workflow_template_versions WHERE workflow_template_id = workflow_templates.id)) " \
                                  "AS projects_count"
                                )
                                .ransack(q_params)
                                .result
                                .order(updated_at: :desc)

    render inertia: "Company/WorkflowTemplates/IndexPage", props: {
      templates: -> { templates.map { |t| WorkflowTemplateResource.new(t).to_h } },
      filters: -> { q_params },
      return_to: -> { safe_return_path(params[:return_to]) },
      project_id: -> { project_id_from_return_to(params[:return_to]) },
      projects: -> { Project.for_user(current_user).order(:name).map { |p| { id: p.id, name: p.name } } },
      current_user_id: -> { current_user.id },
      is_admin: -> { current_user.admin? }
    }
  end

  def create
    source = find_source_workflow
    return_to = safe_return_path(template_params[:return_to])

    WorkflowTemplatePublisher.new(
      source_workflow: source,
      user: current_user,
      company: current_company,
      name: template_params[:name],
      description: template_params[:description],
      use_case: template_params[:use_case],
      visibility: template_params[:visibility] || "company",
      changelog: template_params[:changelog]
    ).publish!

    redirect_to company_workflow_templates_path(return_to: return_to), notice: "Template published"
  rescue WorkflowTemplatePublisher::Error => e
    redirect_back fallback_location: company_workflow_templates_path, alert: e.message
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: company_workflow_templates_path, alert: template_validation_message(e)
  end

  def update
    template = find_manageable_template!
    template.update!(template_params.slice(:name, :description, :use_case, :visibility))
    redirect_to company_workflow_templates_path, notice: "Template updated"
  end

  def publish_version
    template = find_manageable_template!

    source = find_source_workflow
    WorkflowTemplatePublisher.new(
      source_workflow: source,
      user: current_user,
      company: current_company,
      name: template.name,
      description: template.description,
      use_case: template.use_case,
      visibility: template.visibility,
      workflow_template: template,
      changelog: params[:changelog]
    ).publish!

    return_to = safe_return_path(params[:return_to])
    redirect_to company_workflow_templates_path(return_to: return_to), notice: "New version published"
  rescue WorkflowTemplatePublisher::Error => e
    redirect_back fallback_location: company_workflow_templates_path, alert: e.message
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: company_workflow_templates_path, alert: template_validation_message(e)
  end

  private

  def template_validation_message(error)
    return error.message unless error.record.is_a?(WorkflowTemplate)

    if error.record.errors.of_kind?(:name, :taken)
      return "A template with this name already exists in your company catalog."
    end

    error.record.errors.full_messages.join(", ")
  end

  def find_manageable_template!
    template = WorkflowTemplate.visible_to(current_user, current_company).find(params[:id])
    policy = Web::Company::WorkflowTemplatesPolicy.new(policy_context, template)
    raise Pundit::NotAuthorizedError unless policy.update?

    template
  end

  def find_source_workflow
    workflow_id = params[:source_workflow_id] || template_params[:source_workflow_id]
    workflow = Workflow.standard.belonging_to_company(current_company).find(workflow_id)
    workflow
  end

  def template_params
    params.require(:workflow_template).permit(
      :name, :description, :use_case, :visibility, :source_workflow_id, :changelog, :return_to
    )
  end

  def safe_return_path(path)
    return if path.blank?
    return path if path.start_with?("/company/") && !path.start_with?("//")

    nil
  end

  def project_id_from_return_to(path)
    match = safe_return_path(path)&.match(%r{\A/company/projects/(\d+)/workflows\z})
    match&.[](1)&.to_i
  end
end
