# frozen_string_literal: true

module ProjectTeams
  # Every change to a team and its members, with its audit entry and the mail
  # its members get (docs/design/project-teams.md, "Membership"). The web page and
  # the personal MCP tools both go through here; who may call what is their
  # policies' business.
  class Management
    InUse = Class.new(StandardError)

    AUDIT_ACTIONS = {
      created: "team_created", updated: "team_updated", deleted: "team_deleted",
      member_added: "team_member_added", member_removed: "team_member_removed", member_left: "team_member_left"
    }.freeze

    def initialize(project:, actor:)
      @project = project
      @actor = actor
    end

    # @param member_ids [Array<Integer>] the members in the team's order
    def create!(name:, strategy: nil, member_ids: [])
      team = nil
      added = []
      ProjectTeam.transaction do
        team = @project.project_teams.create!(name: name, strategy: strategy.presence || "priority", created_by: @actor)
        audit!(team, :created, { "name" => [ nil, team.name ], "strategy" => [ nil, team.strategy.to_s ] })
        added = sync_members!(team, member_ids)
      end
      notify_added(team, added)
      team
    end

    # Fields left nil are kept; `member_ids` replaces the whole list and its order.
    def update!(team, name: nil, strategy: nil, member_ids: nil)
      added = []
      removed = []
      ProjectTeam.transaction do
        team.name = name unless name.nil?
        team.strategy = strategy unless strategy.nil?
        changes = team.changes.to_hash.slice("name", "strategy").transform_values { |pair| pair.map(&:to_s) }
        team.save!
        audit!(team, :updated, changes) if changes.any?
        unless member_ids.nil?
          member_ids = member_ids.compact_blank.map(&:to_i)
          removed = team.memberships.where.not(user_id: member_ids).includes(:user).map(&:user)
          remove_members!(team, removed, action: :member_removed)
          added = sync_members!(team, member_ids)
        end
      end
      notify_added(team, added)
      removed.each { |user| TeamMailer.removed(user, team, @actor).deliver_later unless user == @actor }
      team
    end

    def destroy!(team)
      triggers = TriggerBinding.where(run_as_team_id: team.id).to_a
      if triggers.any?
        names = triggers.map { |binding| binding.name.presence || binding.workflow&.name || "trigger ##{binding.id}" }
        raise InUse, "Team \"#{team.name}\" is what #{names.to_sentence} run#{'s' if triggers.one?} as — " \
                     "choose someone else for #{triggers.one? ? 'it' : 'them'} first"
      end

      ProjectTeam.transaction do
        audit!(team, :deleted, { "name" => [ team.name, nil ] })
        team.destroy!
      end
    end

    # A member taking themselves out of a team.
    def self.leave!(team, user)
      membership = team.memberships.find_by!(user_id: user.id)
      ProjectTeam.transaction do
        membership.destroy!
        audit!(team, :member_left, { "user_id" => [ user.id, nil ] }, actor: user)
      end
    end

    # Takes `user` out of every team they may no longer be in — after losing a
    # project, a company, a role that starts runs, or after asking to stay out
    # of teams. `company_id` narrows it to that company's projects.
    def self.prune!(user, company_id: nil, reason:)
      memberships = user.project_team_memberships.includes(project_team: :project)
      memberships = memberships.joins(project_team: :project).where(projects: { company_id: company_id }) if company_id
      removed = memberships.to_a.reject do |membership|
        !user.exclude_from_teams? &&
          WorkflowTriggers::RunAs.eligible_users(membership.project).exists?(id: user.id)
      end
      removed.each do |membership|
        team = membership.project_team
        ProjectTeam.transaction do
          membership.destroy!
          audit!(team, :member_removed, { "user_id" => [ user.id, nil ] }, actor: nil,
                 comment: "#{user.email} taken out of team \"#{team.name}\": #{reason}")
        end
      end
      if user.exclude_from_teams?
        notify_owners_of_opt_out(user, removed.map(&:project_team))
      else
        removed.each { |membership| TeamMailer.removed(user, membership.project_team, nil, reason: reason).deliver_later }
      end
      removed.map(&:project_team)
    end

    def self.notify_owners_of_opt_out(user, teams)
      teams.group_by(&:project).each do |project, project_teams|
        owner = project.owner
        next if owner.nil? || owner == user

        TeamMailer.member_opted_out(owner, user, project_teams).deliver_later
      end
    end

    def self.audit!(team, action, changes, actor:, comment: nil)
      Audit.create!(
        auditable: team, associated: team.project, user: actor, username: actor&.email,
        action: AUDIT_ACTIONS.fetch(action), audited_changes: changes,
        comment: comment || "#{actor&.email || 'Aixle'}: #{AUDIT_ACTIONS.fetch(action).humanize.downcase} " \
                            "(team \"#{team.name}\" in project \"#{team.project.name}\")"
      )
    end

    private

    # Adds the members `member_ids` names that are not in yet and puts every
    # listed member at its index. Returns the users added.
    def sync_members!(team, member_ids)
      ids = Array(member_ids).compact_blank.map(&:to_i).uniq
      existing = team.memberships.reset.index_by(&:user_id)
      added = []
      ids.each_with_index do |user_id, position|
        if (membership = existing[user_id])
          membership.update_columns(position: position) if membership.position != position
        else
          user = User.find(user_id)
          team.memberships.create!(user: user, position: position, added_by: @actor)
          audit!(team, :member_added, { "user_id" => [ nil, user.id ] })
          added << user
        end
      end
      added
    end

    def remove_members!(team, users, action:)
      users.each do |user|
        team.memberships.where(user_id: user.id).destroy_all
        audit!(team, action, { "user_id" => [ user.id, nil ] })
      end
    end

    def notify_added(team, users)
      users.each { |user| TeamMailer.added(user, team, @actor).deliver_later unless user == @actor }
    end

    def audit!(team, action, changes)
      self.class.audit!(team, action, changes, actor: @actor)
    end
  end
end
