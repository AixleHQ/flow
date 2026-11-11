# frozen_string_literal: true

require "test_helper"

module ProjectTeams
  class ManagementTest < ActiveSupport::TestCase
    include ActionMailer::TestHelper

    setup do
      @owner = create(:user, :with_company)
      @company = @owner.companies.first
      @project = create(:project, company: @company, owner: @owner)
      @anna = collaborator("Anna")
      @pavel = collaborator("Pavel")
      @management = Management.new(project: @project, actor: @owner)
    end

    def collaborator(name)
      create(:user, company: @company, name: name).tap { |user| @project.add_collaborator(user) }
    end

    test "creating a team puts its members in order, tells each of them, and records it" do
      team = nil
      assert_enqueued_emails(2) do
        team = @management.create!(name: "Planner", strategy: "round_robin", member_ids: [ @pavel.id, @anna.id ])
      end

      assert_equal [ @pavel, @anna ], team.reload.members.to_a
      assert team.round_robin?
      assert_equal @owner, team.created_by
      assert_equal %w[team_created team_member_added team_member_added], Audit.where(auditable: team).order(:id).pluck(:action)
    end

    test "the member list replaces the old one: new members are told they joined, dropped ones that they left" do
      team = @management.create!(name: "Planner", member_ids: [ @anna.id ])
      olga = collaborator("Olga")

      assert_enqueued_email_with(TeamMailer, :removed, args: [ @anna, team, @owner ]) do
        assert_enqueued_email_with(TeamMailer, :added, args: [ olga, team, @owner ]) do
          @management.update!(team, name: "Planners", member_ids: [ @pavel.id, olga.id ])
        end
      end

      assert_equal "Planners", team.reload.name
      assert_equal [ @pavel, olga ], team.members.to_a
      assert Audit.exists?(auditable: team, action: "team_member_removed")
    end

    test "refuses someone outside the project and someone who asked to stay out of teams" do
      outsider = create(:user, company: @company)
      error = assert_raises(ActiveRecord::RecordInvalid) { @management.create!(name: "A", member_ids: [ outsider.id ]) }
      assert_match(/must be a member of the project/, error.message)

      @anna.update!(exclude_from_teams: true)
      error = assert_raises(ActiveRecord::RecordInvalid) { @management.create!(name: "B", member_ids: [ @anna.id ]) }
      assert_match(/asked not to be added to teams/, error.message)
      assert_equal 0, @project.project_teams.count
    end

    test "a team a trigger runs as cannot be deleted; one without leaves its tasks unassigned" do
      team = @management.create!(name: "Planner", member_ids: [ @anna.id ])
      workflow = create(:workflow, scope: @project)
      binding = create(:trigger_binding, project: @project, workflow: workflow, created_by: @owner,
                                         event_type: "webhook.deploy", name: "Nightly", run_as_team: team)

      error = assert_raises(Management::InUse) { @management.destroy!(team) }
      assert_match(/Nightly/, error.message)

      binding.destroy!
      board = create(:board, project: @project)
      task = create(:board_task, board: board, board_column: create(:board_column, board: board), assignee_team: team)
      @management.destroy!(team)

      assert_nil task.reload.assignee_team_id
      assert_equal 0, @project.project_teams.count
    end

    test "a member can leave on their own" do
      team = @management.create!(name: "Planner", member_ids: [ @anna.id, @pavel.id ])

      Management.leave!(team, @anna)

      assert_equal [ @pavel ], team.reload.members.to_a
      assert_equal @anna, Audit.find_by!(auditable: team, action: "team_member_left").user
    end

    test "losing the project, the company or the right to start runs takes a member out of its teams" do
      team = @management.create!(name: "Planner", member_ids: [ @anna.id, @pavel.id ])
      olga = collaborator("Olga")
      @management.update!(team, member_ids: [ @anna.id, @pavel.id, olga.id ])

      assert_enqueued_email_with(TeamMailer, :removed,
                                 args: [ @anna, team, nil, { reason: "no longer a member of project \"#{@project.name}\"" } ]) do
        @project.remove_collaborator(@anna)
      end
      CompanyMembership.find_by!(user: @pavel, company: @company).update!(role: :viewer)
      CompanyMembership.find_by!(user: olga, company: @company).update!(state: :revoked)

      assert_empty team.reload.members
      assert_equal 3, Audit.where(auditable: team, action: "team_member_removed", user: nil).count
    end

    test "asking to stay out of teams takes the user out of every team and tells the project owner" do
      team = @management.create!(name: "Planner", member_ids: [ @anna.id ])

      assert_enqueued_email_with(TeamMailer, :member_opted_out, args: [ @owner, @anna, [ team ] ]) do
        @anna.update!(exclude_from_teams: true)
      end

      assert_empty team.reload.members
    end
  end
end
