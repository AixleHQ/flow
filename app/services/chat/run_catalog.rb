# frozen_string_literal: true

module Chat
  # The workflows a linked person may start from a messenger (docs/design/teams-integration.md
  # §20): in the company the workspace or organization is connected to, in projects
  # where the web would let them start a run, and only workflows that can run
  # unattended, as every run started from chat does.
  module RunCatalog
    # What a picker shows; a key from an older card is still looked up on its own.
    LIMIT = 50

    Entry = Data.define(:project, :workflow) do
      def key = "#{project.id}:#{workflow.id}"
      def title = "#{workflow.name} — #{project.name}"
    end

    module_function

    def entries(user, integration)
      return [] unless member?(user, integration)

      projects = active_projects(integration).includes(:company).select { |project| may_start?(user, project) }.index_by(&:id)
      Workflow.active.where(scope_type: "Project", scope_id: projects.keys).includes(:steps).order(:name)
              .select { |workflow| unattended?(workflow) }
              .first(LIMIT)
              .map { |workflow| Entry.new(project: projects.fetch(workflow.scope_id), workflow: workflow) }
    end

    def find(user, integration, key)
      project_id, workflow_id = key.to_s.split(":", 2)
      return nil unless member?(user, integration)

      project = active_projects(integration).find_by(id: project_id)
      return nil unless project && may_start?(user, project)

      workflow = Workflow.active.where(scope_type: "Project", scope_id: project.id).includes(:steps).find_by(id: workflow_id)
      Entry.new(project: project, workflow: workflow) if workflow && unattended?(workflow)
    end

    def member?(user, integration)
      user.company_memberships.active.exists?(company_id: integration.company_id)
    end

    def active_projects(integration)
      Project.where(company_id: integration.company_id).with_state(:active).order(:name)
    end

    def unattended?(workflow) = workflow.visible_steps.all?(&:allow_non_interactive)

    def may_start?(user, project)
      Web::Company::Projects::WorkflowRunsPolicy.new(ProjectContext.new(user, {}, project: project), project).create?
    end
  end
end
