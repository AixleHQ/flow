# frozen_string_literal: true

require "test_helper"

class PubliclyShareableTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
  end

  test "a run output and a task attachment share and unshare like a project asset" do
    [ run_output, task_attachment ].each do |file|
      token = file.share!(by: @user)

      assert_equal file, PubliclyShareable.find_shared(token)
      assert_includes file.share_url, "/share/#{token}"
      assert_equal @user, file.shared_by
      assert_not_nil file.shared_at

      file.unshare!

      assert_nil PubliclyShareable.find_shared(token)
      assert_nil file.reload.share_url
      assert_nil file.shared_by
    end
  end

  test "a project asset is found by its token too" do
    asset = create(:asset, scope: @project, created_by: @user)

    assert_equal asset, PubliclyShareable.find_shared(asset.share!)
  end

  test "sharing an already shared file keeps its link" do
    file = task_attachment
    token = file.share!

    assert_equal token, file.share!
  end

  test "a blank or unknown token finds nothing" do
    assert_nil PubliclyShareable.find_shared("")
    assert_nil PubliclyShareable.find_shared("unknown")
  end

  private

  def run_output
    run = create(:workflow_run, workflow: create(:workflow, scope: @project), project: @project, user: @user)
    create(:workflow_run_asset, workflow_run: run)
  end

  def task_attachment
    board = create(:board, project: @project)
    task = create(:board_task, board: board, board_column: create(:board_column, board: board))
    create(:task_asset, board_task: task, author: @user)
  end
end
