# frozen_string_literal: true

require "test_helper"

module Activities
  module Workflow
    class PrepareStepListActivityTest < ActiveSupport::TestCase
      setup do
        @company = create(:company)
        @user = create(:user, company: @company)
        @project = create(:project, company: @company, owner: @user)
        @workflow = create(:workflow, scope: @project)
        @run = create(:workflow_run, :running, project: @project, workflow: @workflow, user: @user)

        Rails.logger.stubs(:info)
        Rails.logger.stubs(:warn)
        Rails.logger.stubs(:error)
      end

      test "returns one entry per non-deleted step ordered by position with step metadata" do
        # Created out of position order to prove the activity sorts by position, not insertion.
        step_last = create(:step, workflow: @workflow, position: 3,
          allow_non_interactive: true, on_failure: :skip, max_retries: 5, skip_policy: :manual)
        step_first = create(:step, workflow: @workflow, position: 1)
        step_mid = create(:step, workflow: @workflow, position: 2, depends_on_step_ids: [ step_first.id ])

        # Only the first step has an existing run — its id should be surfaced, the others nil.
        step_run = create(:step_run, workflow_run: @run, step: step_first)

        result = run_activity(PrepareStepListActivity, { "workflow_run_id" => @run.id })

        assert_equal 3, result.length
        assert_equal [ 1, 2, 3 ], result.map { |e| e["position"] }
        assert_equal [ step_first.id, step_mid.id, step_last.id ], result.map { |e| e["step_id"] }
        assert_equal [ step_run.id, nil, nil ], result.map { |e| e["step_run_id"] }
        assert_equal [ step_run.state, nil, nil ], result.map { |e| e["step_run_state"] }
        assert_equal [ 0, 0, 0 ], result.map { |e| e["failed_attempt_count"] }

        # depends_on flows through per step (empty default for the others).
        assert_equal [ [], [ step_first.id ], [] ], result.map { |e| e["depends_on_step_ids"] }

        # Defaults on the first step.
        first = result[0]
        refute first["auto_run"]
        assert_equal "fail", first["on_failure"]
        assert_equal 0, first["max_retries"]
        assert_equal "never", first["skip_policy"]

        # Non-default metadata on the last step is stringified/passed through faithfully.
        last = result[2]
        assert last["auto_run"]
        assert_equal "skip", last["on_failure"]
        assert_equal 5, last["max_retries"]
        assert_equal "manual", last["skip_policy"]
      end

      test "step_overrides auto_run takes precedence over the step's allow_non_interactive both ways" do
        interactive_step = create(:step, workflow: @workflow, position: 1, allow_non_interactive: true)
        auto_step = create(:step, workflow: @workflow, position: 2, allow_non_interactive: false)

        run = create(:workflow_run, :running, project: @project, workflow: @workflow, user: @user,
          step_overrides: {
            interactive_step.id.to_s => { "auto_run" => false },
            auto_step.id.to_s => { "auto_run" => true }
          })

        result = run_activity(PrepareStepListActivity, { "workflow_run_id" => run.id })

        by_step = result.index_by { |e| e["step_id"] }
        # Override flips a non-interactive step off...
        refute by_step[interactive_step.id]["auto_run"]
        # ...and flips an interactive step on.
        assert by_step[auto_step.id]["auto_run"]
      end

      test "surfaces the latest step_run per step, not the first, and counts prior failures" do
        # Simulates a resumed run: the step has an older failed attempt and a
        # newer pending step_run created by the retry — the newer one must win.
        step = create(:step, workflow: @workflow, position: 1)
        older_failed = create(:step_run, workflow_run: @run, step: step, state: "failed")
        older_failed.update!(created_at: 1.hour.ago)
        newer_pending = create(:step_run, workflow_run: @run, step: step, state: "pending")

        result = run_activity(PrepareStepListActivity, { "workflow_run_id" => @run.id })

        entry = result.first
        assert_equal newer_pending.id, entry["step_run_id"]
        assert_equal "pending", entry["step_run_state"]
        assert_equal 1, entry["failed_attempt_count"]
      end

      test "soft-deleted steps are excluded from the list" do
        active_step = create(:step, workflow: @workflow, position: 1)
        deleted_step = create(:step, workflow: @workflow, position: 2, deleted_at: Time.current)

        result = run_activity(PrepareStepListActivity, { "workflow_run_id" => @run.id })

        step_ids = result.map { |e| e["step_id"] }
        assert_equal [ active_step.id ], step_ids
        assert_not_includes step_ids, deleted_step.id
      end
    end
  end
end
