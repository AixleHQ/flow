# frozen_string_literal: true

module WorkflowTriggers
  # Who an off-board trigger's unattended runs belong to: its `created_by`. A
  # column trigger's run belongs to the person the card puts on it
  # (TaskService.run_owner_for), so it has no run-as to change.
  module RunAs
    AUDIT_ACTION = "trigger_run_as_changed"

    module_function

    # What the trigger form needs to offer the change: members only to whoever may make it.
    def options(project, policy)
      editable = policy.change_run_as?
      { editable: editable, members: editable ? candidates(project) : [] }
    end

    # Everyone who may open the project (Project#accessible_by?: its members and
    # the company's admins) and whose company role lets them start runs.
    # Members without an agent are listed, so the picker can say why they can't
    # be chosen.
    def candidates(project)
      users = eligible_users(project).order(:name).to_a
      with_agent = AgentCredential.where(company_id: project.company_id, user_id: users.map(&:id)).distinct.pluck(:user_id)
      users.map { |u| { id: u.id, name: u.name, agent_connected: with_agent.include?(u.id) } }
    end

    def eligible_users(project)
      starters = CompanyMembership.active.where(company_id: project.company_id).where.not(role: :viewer)
      in_project = starters.where(user_id: project.owner_id)
                           .or(starters.where(user_id: project.project_collaborators.select(:user_id)))
      User.where(id: in_project.or(starters.where(role: :admin)).select(:user_id))
    end

    # Why `user` can't own this project's trigger runs, or nil when they can.
    # The rule itself is TaskService.can_own_runs_in?; this only names what failed.
    def ineligibility(project, user)
      return "must be a member of this project" unless project.accessible_by?(user)
      return nil if TaskService.can_own_runs_in?(user, project.company_id)
      return "is a viewer, and viewers can't start runs" if viewers(project).exists?(user_id: user.id)

      "has no agent connected in this company"
    end

    def viewers(project)
      CompanyMembership.active.where(company_id: project.company_id, role: :viewer)
    end

    # Points the binding at `user_id` and saves it through the given block
    # (the callers' own save path), recording the change in the audit trail in
    # the same transaction.
    def save!(binding, actor:, user_id: nil, request: nil)
      binding.created_by_id = user_id if user_id
      change = binding.persisted? && binding.will_save_change_to_created_by_id? ? binding.created_by_id_change : nil

      binding.transaction do
        yield
        audit!(binding, change, actor, request) if change
      end
    end

    def audit!(binding, change, actor, request)
      from_id, to_id = change
      names = User.where(id: [ from_id, to_id ].compact).pluck(:id, :name).to_h
      Audit.create!(
        auditable: binding, associated: binding.project, user: actor, username: actor&.email,
        action: AUDIT_ACTION, audited_changes: { "created_by_id" => [ from_id, to_id ] },
        comment: "#{actor&.email} changed who trigger #{binding.id} runs as from " \
                 "#{names[from_id] || 'nobody'} to #{names[to_id]}",
        remote_address: request&.remote_ip, request_uuid: request&.uuid
      )
    end
  end
end
