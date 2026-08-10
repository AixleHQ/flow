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
      assert_match(/active, finished, failed, all/, result[:stderr])
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

    test "limit is clamped to the cap" do
      create_list(:terminal_session, 3, :agent_session, :running, user: @user, project: @project)

      assert_equal 1, payload(execute(limit: 1))["sessions"].size
      assert_equal 3, payload(execute(limit: 5_000))["sessions"].size
    end
  end
end
