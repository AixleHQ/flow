# frozen_string_literal: true

require "test_helper"

class BuilderProjectSnapshotTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user, name: "Growth")
  end

  test "lists the project's resources with the ids the tools take" do
    workflow = create(:workflow, scope: @project, name: "Weekly report")
    create(:step, workflow: workflow)
    board = create(:board, project: @project)
    column = create(:board_column, board: board, name: "Review", position: 1)
    ColumnWorkflowBinding.create!(board_column: column, workflow: workflow, trigger_mode: "auto")
    agent = create(:agent, scope: @project, title: "Analyst")
    secret = create(:config_item, scope: @project, name: "HUBSPOT_TOKEN", item_type: "secret", value: "s3cr3t-value")

    text = BuilderProjectSnapshot.render(@project, user: @user)

    assert_includes text, "## Project: Growth (id #{@project.id})"
    assert_includes text, "- Weekly report (id #{workflow.id}, 1 step)"
    assert_includes text, "- Review (id #{column.id}) → runs \"Weekly report\" (auto)"
    assert_includes text, "- Analyst (id #{agent.id})"
    assert_includes text, "- HUBSPOT_TOKEN (id #{secret.id}, secret)"
    assert_not_includes text, "s3cr3t-value"
  end

  test "says plainly what is missing" do
    text = BuilderProjectSnapshot.render(@project, user: @user)

    assert_includes text, "no board yet — `setup_board` creates one"
    assert_includes text, "### Workflows\nnone yet"
  end
end
