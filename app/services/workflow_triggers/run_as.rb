# frozen_string_literal: true

module WorkflowTriggers
  # Who an off-board trigger's unattended runs belong to: its `created_by`. A
  # column trigger's run belongs to the person the card puts on it
  # (TaskService.run_owner_for), so it has no run-as to change.
  module RunAs
    AUDIT_ACTION = "trigger_run_as_changed"
    # The default of #save!'s `team_id:`, telling "leave the team as it is" apart from nil.
    KEEP_TEAM = Object.new.freeze

    module_function

    # What the trigger form needs to offer the change: members only to whoever may make it.
    def options(project, policy)
      editable = policy.change_run_as?
      { editable: editable, members: editable ? candidates(project) : [],
        teams: editable ? project.project_teams.map { |team| { id: team.id, name: team.name } } : [] }
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

    # Points the binding at `user_id` or at the team `team_id` (nil clears the
    # team; choosing a person without naming a team clears it too) and saves it
    # through the given block (the callers' own save path), recording the change
    # in the audit trail in the same transaction.
    def save!(binding, actor:, user_id: nil, team_id: KEEP_TEAM, request: nil)
      binding.created_by_id = user_id if user_id
      if !team_id.equal?(KEEP_TEAM)
        binding.run_as_team_id = team_id.presence
      elsif user_id
        binding.run_as_team_id = nil
      end
      changed = binding.persisted? &&
                (binding.will_save_change_to_created_by_id? || binding.will_save_change_to_run_as_team_id?)
      before = describe(binding.created_by_id_was, binding.run_as_team_id_was) if changed

      binding.transaction do
        yield
        audit!(binding, before, actor, request) if changed
      end
    end

    def describe(user_id, team_id)
      return "team #{ProjectTeam.where(id: team_id).pick(:name) || team_id}" if team_id

      User.where(id: user_id).pick(:name) || "nobody"
    end

    def audit!(binding, before, actor, request)
      Audit.create!(
        auditable: binding, associated: binding.project, user: actor, username: actor&.email,
        action: AUDIT_ACTION, audited_changes: binding.saved_changes.to_hash.slice("created_by_id", "run_as_team_id"),
        comment: "#{actor&.email} changed who trigger #{binding.id} runs as from #{before} to " \
                 "#{describe(binding.created_by_id, binding.run_as_team_id)}",
        remote_address: request&.remote_ip, request_uuid: request&.uuid
      )
    end
  end
end
