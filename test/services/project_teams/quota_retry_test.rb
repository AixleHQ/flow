# frozen_string_literal: true

require "test_helper"

module ProjectTeams
  class QuotaRetryTest < ActiveSupport::TestCase
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
      @step_run = create(:step_run, workflow_run: @run, step: @step, state: "failed", error_message: "Out of credits")
    end

    test "hands the run to the next member and records who it moved from" do
      assert QuotaRetry.reassign!(@run, step_run: @step_run)

      assert_equal @pavel, @run.reload.user
      audit = Audit.find_by!(auditable: @run, action: QuotaRetry::AUDIT_ACTION)
      assert_equal({ "user_id" => [ @anna.id, @pavel.id ] }, audit.audited_changes)
    end

    test "keeps the run, and says why, when nobody else can take it" do
      AgentCredential.find_by!(user: @pavel).update_column(:quota_exhausted_until, 1.hour.from_now)

      assert_not QuotaRetry.reassign!(@run, step_run: @step_run)

      assert_equal @anna, @run.reload.user
      assert_match(/Out of credits\n\nNo member of team "Planner" can take this run — Anna: was passed over/, @step_run.reload.error_message)
    end

    test "a run that is not a team's stays where it is" do
      @run.update_columns(team_id: nil)

      assert_not QuotaRetry.reassign!(@run, step_run: @step_run)
      assert_equal @anna, @run.reload.user
    end

    test "the workflow's activity reports whether the run moved" do
      result = run_activity(Activities::Workflow::ReassignRunOwnerActivity,
                            { "workflow_run_id" => @run.id, "step_run_id" => @step_run.id })

      assert_equal({ "reassigned" => true }, result)
    end
  end
end
