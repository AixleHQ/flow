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

    attr_reader :params, :user, :pinned_project, :session

    # `pinned_project:` confines the handler to one project — how the Aixle
    # Builder session serves these tools. Every project lookup below then
    # answers for that project only, so an id naming any other project reads
    # as not found, including a second project param like `target_project_id`.
    # `session:` is the Aixle Builder session serving the call, if any — so a
    # version written by the builder agent names the session, not just the user.
    def initialize(params:, user:, pinned_project: nil, session: nil)
      @params = params.with_indifferent_access
      @user = user
      @pinned_project = pinned_project
      @session = session
    end

    def execute
      raise NotImplementedError, "#{self.class}#execute must be implemented"
    end

    private

    def version_actor
      Versions::Actor.mcp(user, session: session)
    end

    # Optional on every write tool: the version the caller read. A newer one
    # means someone else saved in between, and the call is refused instead of
    # overwriting their change.
    def base_version
      params[:base_version].presence&.to_i
    end

    # Policy gate, UI-equivalent: same policy classes and context objects the
    # controllers use. Raises UnauthorizedError (mapped to an in-band tool
    # error by the MCP handler) when the policy denies.
    # `project:` derives the company from the project (ProjectContext); pass
    # `company:` for the rare company-scoped tool that has no project. Never
    # a "current company" — see #membership_company_ids.
    def authorize!(record, query, policy:, project: nil, company: nil)
      ctx = project ? ProjectContext.new(user, {}, project: project) : BaseContext.new(user, {}, company: company)
      raise UnauthorizedError, "Not allowed to #{query.to_s.delete_suffix('?')} this resource" \
        unless policy.new(ctx, record).public_send(query)

      record
    end

    # A personal-MCP call carries no web session, so there is no
    # `session[:current_company_id]` to lean on: the company is always derived
    # from the target resource, across every company the user actively belongs
    # to. An empty list yields `where(company_id: [])` — i.e. nothing.
    def membership_company_ids
      @membership_company_ids ||= begin
        memberships = user.company_memberships.active
        memberships = memberships.where(company_id: pinned_project.company_id) if pinned_project
        memberships.pluck(:company_id)
      end
    end

    # The single company to act in when a tool has no project to derive one
    # from. Unambiguous only with exactly one active membership; otherwise the
    # caller must name it explicitly.
    def resolve_company!(id = params[:company_id])
      memberships = user.company_memberships.active
      memberships = memberships.where(company_id: pinned_project.company_id) if pinned_project
      membership = id.present? ? memberships.find_by(company_id: id) : sole_membership!(memberships)
      raise NotFoundError, "You are not an active member of company #{id}" unless membership

      membership.company
    end

    # Projects the user can actually reach, in ANY of their companies, filtered
    # by the same accessibility rule the UI uses.
    def find_project!(id = params[:project_id])
      id = pinned_project.id if pinned_project && id.blank?
      scope = Project.where(company_id: membership_company_ids)
      scope = scope.where(id: pinned_project.id) if pinned_project
      project = scope.find_by(id: id)
      raise NotFoundError, "Project #{id} not found" unless project&.accessible_by?(user)

      project
    end

    def accessible_projects
      scope = Project.where(company_id: membership_company_ids)
      scope = scope.where(id: pinned_project.id) if pinned_project
      scope.select { |p| p.accessible_by?(user) }
    end

    # A session the user may look at: reachable (their own, or in a project they
    # can reach) AND shared by its owner for this phase of its life
    # (TerminalSession#visible_to?). Not-found rather than not-allowed, so a
    # session someone keeps private is indistinguishable from one that does not
    # exist — the same rule Api::V1::TerminalSessionsController applies.
    def find_session!(id = params[:session_id])
      scope = TerminalSession.readable_by(user)
      scope = scope.where(project_id: pinned_project.id) if pinned_project
      session = scope.find_by(id: id)
      raise NotFoundError, "Session #{id} not found" unless session&.visible_to?(user)

      session
    end

    # The acting user's OWN membership in the session's company — not
    # SessionCompany.membership_for, which answers for the session's owner. Used
    # to keep read-only members out of write paths.
    def session_membership(session)
      company_id = SessionCompany.company_id_for(session)
      return nil if company_id.blank?

      user.company_memberships.active.find_by(company_id: company_id)
    end

    # A run of THIS project that this user may steer. Two separate refusals:
    # a run of another project does not exist as far as the caller is concerned,
    # and a run they can see but not steer is a denial with a reason — the same
    # rule the run screen applies (WorkflowRun#controllable_by?).
    def find_controllable_run!(project, id = params[:run_id])
      run = WorkflowRun.where(project: project).find_by(id: id)
      raise NotFoundError, "Run #{id} not found in this project" unless run
      unless run.controllable_by?(user)
        raise UnauthorizedError,
          "Run #{run.id} was started by #{run.user&.name.presence || 'someone else'} — only they or a company admin can control it"
      end

      run
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

    def find_sub_step!(step, id = params[:sub_step_id])
      sub_step = step.sub_steps.active.find_by(id: id)
      raise NotFoundError, "Sub-step #{id} not found in this step" unless sub_step

      sub_step
    end

    # Ambiguity is an error, never a silent pick: a multi-company user writing
    # into the wrong company is not recoverable from the agent's side.
    def sole_membership!(memberships)
      loaded = memberships.to_a
      return loaded.first if loaded.one?

      raise NotFoundError, "You belong to no company" if loaded.empty?

      raise NotFoundError,
            "You belong to #{loaded.size} companies — pass company_id (see list_companies)"
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
