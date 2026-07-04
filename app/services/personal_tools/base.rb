# frozen_string_literal: true

module PersonalTools
  # Base for personal-MCP tool handlers: session-less, authenticated as a
  # User via their personal token. Every data access MUST go through the same
  # Pundit policies the UI uses — the token grants exactly the user's own
  # access level, nothing more. Declare tools with the same `tool do` DSL as
  # InternalTools, plus `audience :user`.
  class Base
    extend Tools::DefinitionDSL

    class UnauthorizedError < StandardError; end
    class NotFoundError < StandardError; end

    attr_reader :params, :user

    def initialize(params:, user:)
      @params = params.with_indifferent_access
      @user = user
    end

    def execute
      raise NotImplementedError, "#{self.class}#execute must be implemented"
    end

    private

    # Policy gate, UI-equivalent: same policy classes and context objects the
    # controllers use. Raises UnauthorizedError (mapped to an in-band tool
    # error by the MCP handler) when the policy denies.
    def authorize!(record, query, policy:, project: nil)
      ctx = project ? ProjectContext.new(user, {}, project: project) : BaseContext.new(user, {})
      raise UnauthorizedError, "Not allowed to #{query.to_s.delete_suffix('?')} this resource" \
        unless policy.new(ctx, record).public_send(query)

      record
    end

    # Projects the user can actually reach: their company's, filtered by the
    # same accessibility rule the UI uses.
    def find_project!(id = params[:project_id])
      project = user.company && Project.where(company: user.company).find_by(id: id)
      raise NotFoundError, "Project #{id} not found" unless project&.accessible_by?(user)

      project
    end

    def accessible_projects
      return Project.none if user.company.nil?

      Project.where(company: user.company).select { |p| p.accessible_by?(user) }
    end

    # A workflow scoped to the project — never a global Workflow.find, so a
    # user can't reach another project's workflow by id.
    def find_workflow!(project, id = params[:workflow_id])
      workflow = Workflow.visible_for_project(project).find_by(id: id)
      raise NotFoundError, "Workflow #{id} not found in this project" unless workflow

      workflow
    end

    def find_step!(workflow, id = params[:step_id])
      step = workflow.steps.not_deleted.find_by(id: id)
      raise NotFoundError, "Step #{id} not found in this workflow" unless step

      step
    end

    def success(payload)
      text = payload.is_a?(String) ? payload : JSON.pretty_generate(payload.as_json)
      { exit_code: 0, stdout: text, stderr: "" }
    end

    def error(text)
      { exit_code: 1, stdout: "", stderr: text.to_s }
    end
  end
end
