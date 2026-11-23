# frozen_string_literal: true

require "test_helper"

module PersonalTools
  class ListSessionsTest < ActiveSupport::TestCase
    setup do
      @user = create(:user, :with_company)
      @company = @user.companies.first
      @project = create(:project, owner: @user, company: @company)
    end

    def execute(**params)
      ListSessions.new(params: params, user: @user).execute
    end

    def payload(result) = JSON.parse(result[:stdout])

    def queries_during(&)
      count = 0
      counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &)
      count
    end

    test "lists the caller's active sessions newest first and leaves finished ones out" do
      running = create(:terminal_session, :agent_session, :running, user: @user, project: @project)
      finished = create(:terminal_session, :agent_session, :collected, user: @user, project: @project)

      ids = payload(execute)["sessions"].map { |s| s["id"] }

      assert_includes ids, running.id
      assert_not_includes ids, finished.id
    end

    test "state: finished lists the finished ones instead" do
      finished = create(:terminal_session, :agent_session, :collected, user: @user, project: @project)

      ids = payload(execute(state: "finished"))["sessions"].map { |s| s["id"] }

      assert_equal [ finished.id ], ids
    end

    test "an unknown state is refused, naming the allowed values" do
      result = execute(state: "wedged")

      assert_equal 1, result[:exit_code]
      assert_match(/active, finished, failed, cancelled, all/, result[:stderr])
    end

    test "an unknown sort column and an unreadable day are refused" do
      assert_match(/created_at, cost_cents, total_tokens, duration_seconds/, execute(sort: "name")[:stderr])
      assert_match(/YYYY-MM-DD/, execute(created_from: "last week")[:stderr])
    end

    test "another member's active session is hidden unless they share active sessions" do
      other = create(:user)
      create(:company_membership, user: other, company: @company, role: :employee)
      theirs = create(:terminal_session, :agent_session, :running, user: other, project: @project)

      assert_not_includes payload(execute)["sessions"].map { |s| s["id"] }, theirs.id

      other.update!(share_active_sessions: true)
      assert_includes payload(execute)["sessions"].map { |s| s["id"] }, theirs.id
    end

    test "a session in another company is never listed" do
      stranger = create(:user, :with_company)
      elsewhere = create(:project, owner: stranger, company: stranger.companies.first)
      theirs = create(:terminal_session, :agent_session, :running, user: stranger, project: elsewhere)

      assert_not_includes payload(execute(state: "all"))["sessions"].map { |s| s["id"] }, theirs.id
    end

    test "project_id narrows the listing" do
      other_project = create(:project, owner: @user, company: @company)
      here = create(:terminal_session, :agent_session, :running, user: @user, project: @project)
      there = create(:terminal_session, :agent_session, :running, user: @user, project: other_project)

      ids = payload(execute(project_id: @project.id))["sessions"].map { |s| s["id"] }

      assert_equal [ here.id ], ids
      assert_not_includes ids, there.id
    end

    test "rows carry the workflow linkage but not the metadata blob" do
      session = create(:terminal_session, :running, user: @user, project: @project,
                       session_type: "workflow_step",
                       metadata: { "workflow_run_id" => 42, "step_run_id" => 7, "step_name" => "Build",
                                   "initial_prompt" => "secret plan" })

      row = payload(execute)["sessions"].find { |s| s["id"] == session.id }

      assert_equal 42, row["workflow_run_id"]
      assert_equal "Build", row["step_name"]
      assert_not_includes row.keys, "metadata"
      assert_not_includes row.to_s, "secret plan"
    end

    test "listing more sessions costs no more queries" do
      create(:terminal_session, :agent_session, :running, user: @user, project: @project)
      one = queries_during { execute }
      create_list(:terminal_session, 3, :agent_session, :running, user: @user, project: @project)

      assert_equal one, queries_during { execute }
    end

    test "offset pages through every session, past what one page holds" do
      sessions = create_list(:terminal_session, 5, :agent_session, :collected, user: @user, project: @project)

      pages = [ 0, 2, 4 ].map { |offset| payload(execute(state: "all", limit: 2, offset: offset)) }

      assert_equal sessions.map(&:id).sort, pages.flat_map { |p| p["sessions"].map { |s| s["id"] } }.sort
      assert_equal [ 5, 5, 5 ], pages.map { |p| p["total"] }
      assert_equal [ true, true, false ], pages.map { |p| p["has_more"] }
    end

    test "a session the caller may not see takes no place on a page or in the total" do
      other = create(:user, share_completed_sessions: false)
      create(:company_membership, user: other, company: @company, role: :employee)
      create_list(:terminal_session, 3, :agent_session, :collected, user: other, project: @project)
      mine = create(:terminal_session, :agent_session, :collected, user: @user, project: @project,
                                       created_at: 1.day.ago)

      listed = payload(execute(state: "all", limit: 1))

      assert_equal 1, listed["total"]
      assert_equal [ mine.id ], listed["sessions"].map { |s| s["id"] }
    end

    test "created_from and created_until take whole days" do
      before = create(:terminal_session, :agent_session, :collected, user: @user, project: @project,
                                         created_at: Time.utc(2026, 11, 15, 23, 59))
      inside = [ Time.utc(2026, 11, 16, 0, 0), Time.utc(2026, 11, 22, 23, 59) ].map do |at|
        create(:terminal_session, :agent_session, :collected, user: @user, project: @project, created_at: at)
      end

      ids = payload(execute(state: "all", created_from: "2026-11-16", created_until: "2026-11-22"))["sessions"]
              .map { |s| s["id"] }

      assert_equal inside.map(&:id).sort, ids.sort
      assert_not_includes ids, before.id
    end

    test "sort and direction order the rows, and totals sum every match rather than the page" do
      small, big, middle = [ 10, 300, 50 ].map do |tokens|
        create(:terminal_session, :agent_session, :collected, user: @user, project: @project,
                                  total_tokens: tokens, input_tokens: tokens, cost_cents: tokens / 10)
      end

      top = payload(execute(state: "all", sort: "total_tokens", limit: 2))
      bottom = payload(execute(state: "all", sort: "total_tokens", direction: "asc", limit: 1))

      assert_equal [ big.id, middle.id ], top["sessions"].map { |s| s["id"] }
      assert_equal "total_tokens desc", top["sort"]
      assert_equal [ small.id ], bottom["sessions"].map { |s| s["id"] }
      assert_equal 360, top["totals"]["total_tokens"]
      assert_equal 360, top["totals"]["input_tokens"]
      assert_equal 36, top["totals"]["cost_cents"]
      assert_equal 300, top["sessions"].first["total_tokens"]
    end

    test "session_type, agent_type, user_id and search narrow the listing" do
      other = create(:user, share_completed_sessions: true)
      create(:company_membership, user: other, company: @company, role: :employee)
      solo = create(:terminal_session, :agent_session, :collected, user: @user, project: @project,
                                       initial_prompt: "Fix the 100% CPU bug")
      step = create(:terminal_session, :collected, session_type: "workflow_step", user: @user, project: @project)
      codex = create(:terminal_session, :agent_session, :collected, user: @user, project: @project, agent_type: "codex")
      theirs = create(:terminal_session, :agent_session, :collected, user: other, project: @project)

      listed = ->(**filters) { payload(execute(state: "all", **filters))["sessions"].map { |s| s["id"] }.sort }

      assert_equal [ step.id ], listed.call(session_type: "workflow_step")
      assert_equal [ codex.id ], listed.call(agent_type: "codex")
      assert_equal [ theirs.id ], listed.call(user_id: other.id)
      assert_equal [ solo.id ], listed.call(search: "100% cpu")
    end

    test "workflow_id keeps the step sessions of that workflow's runs" do
      workflow = create(:workflow, scope: @project)
      run = create(:workflow_run, workflow: workflow, project: @project, user: @user)
      step = create(:terminal_session, :collected, session_type: "workflow_step", user: @user, project: @project)
      create(:step_run, workflow_run: run, terminal_session: step)
      create(:terminal_session, :collected, session_type: "workflow_step", user: @user, project: @project)

      ids = payload(execute(state: "all", workflow_id: workflow.id))["sessions"].map { |s| s["id"] }

      assert_equal [ step.id ], ids
    end

    test "company_id narrows to one company and refuses one the caller is not in" do
      second = create(:company)
      create(:company_membership, user: @user, company: second, role: :employee)
      there = create(:terminal_session, :agent_session, :collected, user: @user,
                                        project: create(:project, owner: @user, company: second))
      create(:terminal_session, :agent_session, :collected, user: @user, project: @project)

      ids = payload(execute(state: "all", company_id: second.id))["sessions"].map { |s| s["id"] }

      assert_equal [ there.id ], ids
      assert_raises(Base::NotFoundError) { execute(company_id: create(:company).id) }
    end

    test "limit is clamped to the cap" do
      create_list(:terminal_session, 3, :agent_session, :running, user: @user, project: @project)

      assert_equal 1, payload(execute(limit: 1))["sessions"].size
      assert_equal 3, payload(execute(limit: 5_000))["sessions"].size
    end
  end
end
