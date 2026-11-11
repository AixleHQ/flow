# frozen_string_literal: true

# A project team runs work on its members' own agent subscriptions, so a member
# hears when they are put in a team or taken out of one
# (docs/design/project-teams.md, "Membership").
class TeamMailer < ApplicationMailer
  def added(user, team, actor)
    @team = team
    @project = team.project
    @actor = actor
    @profile_url = profile_url(host: Settings.domain, protocol: Settings.protocol)

    mail(to: user.email, subject: "You were added to team #{team.name} in #{@project.name}")
  end

  # `reason` is set when nobody took them out: they lost what being in a team takes.
  def removed(user, team, actor, reason: nil)
    @team = team
    @project = team.project
    @actor = actor
    @reason = reason

    mail(to: user.email, subject: "You were taken out of team #{team.name} in #{@project.name}")
  end

  # To a project's owner, when a member of its teams asked to stay out of teams.
  def member_opted_out(owner, member, teams)
    @member = member
    @teams = teams
    @project = teams.first.project
    @teams_url = company_project_teams_url(@project, host: Settings.domain, protocol: Settings.protocol)

    mail(to: owner.email, subject: "#{member.name} left the teams of #{@project.name}")
  end
end
