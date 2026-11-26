# frozen_string_literal: true

require "test_helper"

module PersonalTools
  class ListWorkflowRunsTest < ActiveSupport::TestCase
    setup do
      @user = create(:user, :with_company)
      @company = @user.companies.first
      @project = create(:project, owner: @user, company: @company)
      @workflow = create(:workflow, scope: @project, name: "Nightly triage")
      @step = create(:step, workflow: @workflow, position: 1)
    end

    def execute(**params)
      ListWorkflowRuns.new(params: { project_id: @project.id, **params }, user: @user).execute
    end

    def payload(result) = JSON.parse(result[:stdout])
    def ids(result) = payload(result)["runs"].map { |r| r["id"] }

    def run_with_step(state: "completed", session_state: "finished", tokens: 0, workflow: @workflow, **attrs)
      run = create(:workflow_run, workflow: workflow, project: @project, user: @user, state: state, **attrs)
      session = create(:terminal_session, session_type: "workflow_step", user: @user, project: @project,
                                          state: session_state, total_tokens: tokens, cost_cents: tokens / 10)
      create(:step_run, workflow_run: run, step: @step, terminal_session: session,
                        state: state == "completed" ? "completed" : "running")
      run
    end

    def queries_during(&)
      count = 0
      counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &)
      count
    end

    test "offset pages through every run, past what one page holds" do
      runs = Array.new(5) { run_with_step }

      pages = [ 0, 2, 4 ].map { |offset| payload(execute(limit: 2, offset: offset)) }

      assert_equal runs.map(&:id).sort, pages.flat_map { |p| p["runs"].map { |r| r["id"] } }.sort
      assert_equal [ 5, 5, 5 ], pages.map { |p| p["total"] }
      assert_equal [ true, true, false ], pages.map { |p| p["has_more"] }
    end

    test "rows carry the workflow's name and the tokens and cost of the run's step sessions" do
      run = run_with_step(tokens: 400)

      row = payload(execute)["runs"].find { |r| r["id"] == run.id }

      assert_equal "Nightly triage", row["workflow_name"]
      assert_equal [ false, nil ], row.values_at("draft_test", "draft_of_workflow_id")
      assert_equal 400, row["total_tokens"]
      assert_equal 40, row["cost_cents"]
      assert_equal 1, row["steps_completed"]
    end

    test "sort by total_tokens puts the most expensive run first" do
      small, big = [ 10, 900 ].map { |tokens| run_with_step(tokens: tokens) }

      listed = payload(execute(sort: "total_tokens"))

      assert_equal [ big.id, small.id ], listed["runs"].map { |r| r["id"] }
      assert_equal "total_tokens desc", listed["sort"]
    end

    test "state takes the Sessions & Runs statuses, and queued means a step waiting for a slot" do
      done = run_with_step
      failed = run_with_step(state: "failed", session_state: "failed")
      parked = run_with_step(state: "running", session_state: "queued")

      assert_equal [ done.id ], ids(execute(state: "completed"))
      assert_equal [ failed.id ], ids(execute(state: "failed"))
      assert_equal [ parked.id ], ids(execute(state: "queued"))
      assert_equal "queued", payload(execute(state: "queued"))["runs"].first["state"]
    end

    test "workflow_id, user_id, search and the date range narrow the listing" do
      other_workflow = create(:workflow, scope: @project, name: "Release notes")
      colleague = create(:user)
      create(:company_membership, user: colleague, company: @company, role: :employee)
      mine = run_with_step(created_at: Time.utc(2026, 11, 18, 12))
      release = run_with_step(workflow: other_workflow, created_at: Time.utc(2026, 11, 10, 12))
      theirs = create(:workflow_run, workflow: @workflow, project: @project, user: colleague)

      assert_equal [ release.id ], ids(execute(workflow_id: other_workflow.id))
      assert_equal [ theirs.id ], ids(execute(user_id: colleague.id))
      assert_equal [ release.id ], ids(execute(search: "release"))
      assert_equal [ mine.id ], ids(execute(created_from: "2026-11-16", created_until: "2026-11-22"))
    end

    test "task_number narrows the listing to the runs started for that board task" do
      board = create(:board, project: @project)
      column = create(:board_column, board: board)
      task, other = create_list(:board_task, 2, board: board, board_column: column)
      for_task = run_with_step(board_task: task)
      run_with_step(board_task: other)
      run_with_step

      listed = payload(execute(task_number: task.number))["runs"]

      assert_equal [ [ for_task.id, task.number, task.title ] ],
                   listed.map { |r| r.values_at("id", "task_number", "task_title") }
    end

    test "an unknown state or sort, and an unreadable day, are refused" do
      assert_match(/queued, running, completed, failed, cancelled, pending, all/, execute(state: "done")[:stderr])
      assert_match(/created_at, cost_cents/, execute(sort: "name")[:stderr])
      assert_match(/YYYY-MM-DD/, execute(created_until: "yesterday")[:stderr])
    end

    test "listing more runs costs no more queries" do
      run_with_step
      one = queries_during { execute }
      3.times { run_with_step }

      assert_equal one, queries_during { execute }
    end
  end
end
