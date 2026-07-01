# frozen_string_literal: true

class Web::Company::WorkflowCatalogController < Web::Company::ApplicationController
  def index
    workflows = Workflow.published_in_company(current_company)
                        .includes(:steps, :published_by)
                        .order(published_at: :desc)

    projects = Project.for_user(current_user).order(:name)

    render inertia: "Company/WorkflowCatalog/IndexPage", props: {
      workflows: -> { workflows.map { |w| catalog_workflow_props(w) } },
      projects: -> { projects.map { |p| { id: p.id, name: p.name } } }
    }
  end

  def duplicate
    workflow = Workflow.published_in_company(current_company).find(params[:id])
    project = Project.for_user(current_user).find(params[:project_id])

    duplicator = WorkflowDuplicator.new(workflow, target_scope: project)
    copy = duplicator.duplicate!

    flash[:notice] = "Workflow and its resources copied to #{project.name}. Assets, repositories, integrations and secrets are not copied."
    flash[:needs_setup] = duplicator.summary[:needs_setup] if duplicator.summary

    redirect_to builder_company_project_workflow_path(project, copy)
  rescue ActiveRecord::RecordNotFound
    redirect_to company_workflow_catalog_index_path, alert: "Workflow or project not found"
  end

  private

  def catalog_workflow_props(workflow)
    {
      id: workflow.id,
      name: workflow.name,
      description: workflow.description,
      scope_type: workflow.scope_type,
      steps_count: workflow.steps.select { |s| s.deleted_at.nil? }.size,
      published_at: workflow.published_at&.iso8601,
      published_by_name: workflow.published_by&.name
    }
  end
end
