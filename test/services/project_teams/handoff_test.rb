# frozen_string_literal: true

require "test_helper"

module ProjectTeams
  class HandoffTest < ActiveSupport::TestCase
    setup do
      @owner = create(:user, :with_company)
      @company = @owner.companies.first
      @project = create(:project, company: @company, owner: @owner)
      @workflow = create(:workflow, scope: @project)
      @step = create(:step, workflow: @workflow)
      @anna, @pavel = %w[Anna Pavel].map do |name|
        create(:user, company: @company, name: name).tap do |user|
          @project.add_collaborator(user)
          create(:agent_credential, user: user, company: @company, agent_type: "kiro_cli")
        end
      end
      @team = Management.new(project: @project, actor: @owner).create!(name: "Planner", member_ids: [ @anna.id, @pavel.id ])
      @run = create(:workflow_run, :running, project: @project, workflow: @workflow, user: @anna, team: @team)
      @step_run = create(:step_run, workflow_run: @run, step: @step, state: "failed", error_message: "Out of credits",
                                    error_category: "quota_exceeded")
    end

    test "hands the run to the next member and records who it moved from" do
      @run.mark_quota_failed!(credential_id: AgentCredential.find_by!(user: @anna).id)

      assert Handoff.reassign!(@run, step_run: @step_run)

      @run.reload
      assert_equal @pavel, @run.user
      assert_nil @run.failure_reason, "the stop no longer says why the run ends"
      assert_nil @run.failed_agent_credential_id
      audit = Audit.find_by!(auditable: @run, action: Handoff::AUDIT_ACTION)
      assert_equal({ "user_id" => [ @anna.id, @pavel.id ] }, audit.audited_changes)
      assert_match(/after a quota stop on step run #{@step_run.id}/, audit.comment)
    end

    # A failed login holds nothing, so only the run's own history keeps it from
    # going back to a member it has already left.
    test "never hands a run back to a member it has already left" do
      olga = create(:user, company: @company, name: "Olga").tap do |user|
        @project.add_collaborator(user)
        create(:agent_credential, user: user, company: @company, agent_type: "kiro_cli")
      end
      Management.new(project: @project, actor: @owner).update!(@team, member_ids: [ @anna.id, @pavel.id, olga.id ])
      @step_run.update!(error_category: "auth_expired")

      assert Handoff.reassign!(@run.reload, step_run: @step_run)
      assert_equal @pavel, @run.reload.user
      assert Handoff.reassign!(@run, step_run: @step_run)
      assert_equal olga, @run.reload.user
      assert_not Handoff.reassign!(@run, step_run: @step_run)
      assert_equal olga, @run.reload.user
      assert_match(/after a login failure/, Audit.where(auditable: @run).last.comment)
    end

    test "keeps the run, and says why, when nobody else can take it" do
      AgentCredential.find_by!(user: @pavel).update_column(:quota_exhausted_until, 1.hour.from_now)

      assert_not Handoff.reassign!(@run, step_run: @step_run)

      assert_equal @anna, @run.reload.user
      assert_match(/Out of credits\n\nNo member of team "Planner" can take this run — Anna: was passed over/, @step_run.reload.error_message)
    end

    test "a run that is not a team's stays where it is" do
      @run.update_columns(team_id: nil)

      assert_not Handoff.reassign!(@run, step_run: @step_run)
      assert_equal @anna, @run.reload.user
    end

    test "the workflow's activity reports whether the run moved" do
      result = run_activity(Activities::Workflow::ReassignRunOwnerActivity,
                            { "workflow_run_id" => @run.id, "step_run_id" => @step_run.id })

      assert_equal({ "reassigned" => true }, result)
    end
  end
end
