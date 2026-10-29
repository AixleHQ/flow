# frozen_string_literal: true

require "test_helper"

class Admin::ProjectMovesTest < ActionDispatch::IntegrationTest
  setup do
    @s = ProjectMoveScenario.new.build
    @admin = create(:user, :super_admin, password: AuthHelper::TEST_PASSWORD)
  end

  test "only a super admin reaches the move" do
    sign_in_as(@s.owner)

    get new_admin_project_move_path(@s.project)
    assert_redirected_to admin_login_path

    post admin_project_move_path(@s.project), params: move_params
    assert_redirected_to admin_login_path
    assert_equal @s.source, @s.project.reload.company
  end

  test "the preflight lists what the move will do" do
    sign_in_as(@admin)

    get new_admin_project_move_path(@s.project, target_company_id: @s.target.id)

    assert_response :success
    body = response.body
    assert_includes body, "Launchpad (2)"
    assert_includes body, "handbook/style.md"
    assert_includes body, "northwind/site"
    assert_includes body, "Run ##{@s.pending_run.id}"
    assert_includes body, @s.outsider.email
    assert_includes body, "Ask in Slack"
    assert_includes body, "reserved 2 concurrent sessions"
  end

  test "the preflight and the report list the workflows that switch to Hosted" do
    runner = create(:runner, company: @s.source, name: "Prod VPC")
    @s.workflow.update!(runner: runner)
    create(:workflow, scope: @s.project, name: "Hotfix", runner: runner, deleted_at: Time.current)
    sign_in_as(@admin)

    get new_admin_project_move_path(@s.project, target_company_id: @s.target.id)

    assert_response :success
    assert_includes response.body, "Workflows to switch to Hosted"
    assert_includes response.body, "Hotfix (archived) — was on runner Prod VPC"
    assert_includes response.body, "Release — was on runner Prod VPC"

    post admin_project_move_path(@s.project), params: move_params
    follow_redirect!

    assert_includes response.body, "Workflows switched to Hosted"
    assert_nil @s.workflow.reload.runner_id
  end

  test "moving shows the report and leaves it on the project" do
    sign_in_as(@admin)

    post admin_project_move_path(@s.project), params: move_params

    assert_redirected_to admin_project_move_path(@s.project)
    assert_equal @s.target, @s.project.reload.company
    follow_redirect!
    assert_response :success
    assert_includes response.body, "Moved from <strong>Northwind</strong> to\n    <strong>Contoso</strong>"
    assert_includes response.body, @s.outsider.email

    get admin_project_path(@s.project)
    assert_includes response.body, "Last move"
  end

  test "a refused move goes back to the preflight with the reason" do
    sign_in_as(@admin)

    post admin_project_move_path(@s.project), params: move_params(member_policy: "block")

    assert_redirected_to new_admin_project_move_path(@s.project, target_company_id: @s.target.id)
    follow_redirect!
    assert_includes response.body, "is not a member of Contoso"
    assert_equal @s.source, @s.project.reload.company
  end

  test "the project edit form no longer changes the company" do
    sign_in_as(@admin)

    patch admin_project_path(@s.project), params: { project: { company_id: @s.target.id, name: "Renamed" } }

    project = @s.project.reload
    assert_equal [ @s.source, "Renamed" ], [ project.company, project.name ]
  end

  private

  def move_params(member_policy: "add")
    { target_company_id: @s.target.id, owner_id: @s.owner.id, member_policy: member_policy, confirm_cancellations: "1" }
  end
end
