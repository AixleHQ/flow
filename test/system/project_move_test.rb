# frozen_string_literal: true

require "application_system_test_case"

# E2E critical path: a super admin moves a fully populated project into another
# company from the back office, through a headless browser. The services' own
# tests cover each rule; this covers the screens an operator actually clicks
# through — preflight, people, confirmation, report — against the real stack.
class ProjectMoveTest < ApplicationSystemTestCase
  setup do
    @s = ProjectMoveScenario.new.build
    @admin = create(:user, :super_admin, password: AuthHelper::TEST_PASSWORD)
    AdminLoginPage.new.tap(&:load).sign_in(@admin.email, AuthHelper::TEST_PASSWORD)
    assert_current_path "/admin", wait: 10
  end

  test "a super admin moves a project with all its data into another company" do
    ids = snapshot_ids

    visit "/admin/projects/#{@s.project.id}"
    click_link "Move to another company"

    move_page = AdminProjectMovePage.new
    move_page.preview("Contoso")
    assert_text "Will be renamed"
    assert_text "Launchpad (2)"
    assert_text "handbook/style.md"
    assert_text "northwind/site"
    assert_text "Run ##{@s.pending_run.id}"
    assert_text "People who are not in Contoso"
    assert_text @s.outsider.email

    move_page.choose_member_policy("Add them to Contoso as employees")
    move_page.move(owner_email: @s.owner.email)

    assert_text "Launchpad (2) moved to Contoso.", wait: 10
    assert_text "Moved from Northwind to Contoso"
    assert_text "Repositories detached"
    assert_text "Company assets copied into the project"

    project = @s.project.reload
    assert_equal [ @s.target, "Launchpad (2)" ], [ project.company, project.name ]
    assert_equal ids, snapshot_ids
    assert_nil @s.company_repository.reload.integration_id
    assert_equal "cancelled", @s.pending_run.reload.state
    assert_includes project.collaborators, @s.outsider
    copy = Asset.find_by!(scope: project, folder: "handbook", name: "style.md")
    assert_equal [ copy.id ], @s.step.reload.asset_ids
  end

  private

  # What a person or an integration outside holds on to: none of it may change.
  def snapshot_ids
    project = @s.project
    {
      board: project.board.id,
      tasks: BoardTask.where(board: project.board).order(:id).pluck(:id, :number, :parent_task_id),
      comments: TaskComment.where(board_task: @s.parent_task).pluck(:id),
      workflows: Workflow.where(scope: project).pluck(:id),
      runs: project.workflow_runs.order(:id).pluck(:id),
      triggers: TriggerBinding.where(project: project).order(:id).pluck(:id),
      webhook: @s.webhook_endpoint.reload.slug,
      config_items: ConfigItem.where(scope: project).pluck(:id)
    }
  end
end
