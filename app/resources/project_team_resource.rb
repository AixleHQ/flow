# frozen_string_literal: true

# A project team as its page shows it: the members in the team's order, each with
# whether they can take a run now, who the next run would go to, and what uses
# the team. A list passes `params[:context]` (.context_for) instead of querying
# per team.
class ProjectTeamResource < ApplicationResource
  typelize_from ProjectTeam

  attributes :id, :name, :project_id

  typelize "'priority' | 'round_robin' | 'most_remaining'"
  attribute :strategy do |team|
    team.strategy.to_s
  end

  typelize "Array<{ id: number; name: string; email: string; " \
           "status: { state: 'ready' | 'on_hold' | 'unavailable'; until: string | null; detail: string | null }; " \
           "runtimes: Array<{ agentType: string; label: string; quotaExhaustedUntil: string | null }> }>"
  attribute :members do |team|
    skipped = preview(team).skipped.index_by { |skip| skip.user.id }
    memberships = team.memberships.to_a
    credentials = AgentCredential.where(company_id: team.project.company_id, user_id: memberships.map(&:user_id))
                                 .order(:agent_type).group_by(&:user_id)
    memberships.map do |membership|
      user = membership.user
      skip = skipped[user.id]
      {
        id: user.id, name: user.name, email: user.email,
        status: if skip
                  { state: skip.held_until ? "on_hold" : "unavailable", until: skip.held_until&.iso8601,
                    detail: skip.reason }
                else
                  { state: "ready", until: nil, detail: nil }
                end,
        runtimes: credentials.fetch(user.id, []).map do |credential|
          { agent_type: credential.agent_type, label: AgentRuntime.label_for(credential.agent_type),
            quota_exhausted_until: (credential.quota_exhausted_until&.iso8601 if credential.quota_exhausted?) }
        end
      }
    end
  end

  # Who the next run would go to, for a run that pins no runtime.
  typelize "number | null"
  attribute :next_member_id do |team|
    preview(team).next_user&.id
  end

  typelize "Array<{ id: number; name: string | null; workflowName: string | null }>"
  attribute :triggers do |team|
    bindings = params[:context] ? params[:context][:triggers].fetch(team.id, []) : team.trigger_bindings.includes(:workflow)
    bindings.map { |binding| { id: binding.id, name: binding.name, workflow_name: binding.workflow&.name } }
  end

  typelize :number
  attribute :trigger_count do |team|
    params[:context] ? params[:context][:triggers].fetch(team.id, []).size : team.trigger_bindings.count
  end

  typelize :number
  attribute :task_count do |team|
    params[:context] ? params[:context][:tasks].fetch(team.id, 0) : team.assigned_tasks.active.count
  end

  def self.context_for(teams)
    ids = teams.map(&:id)
    { triggers: TriggerBinding.where(run_as_team_id: ids).includes(:workflow).order(:id).group_by(&:run_as_team_id),
      tasks: BoardTask.active.where(assignee_team_id: ids).group(:assignee_team_id).count,
      previews: teams.to_h { |team| [ team.id, ProjectTeams::Picker.preview(team) ] } }
  end

  private

  def preview(team)
    params[:context]&.dig(:previews, team.id) || (@preview ||= ProjectTeams::Picker.preview(team))
  end
end
