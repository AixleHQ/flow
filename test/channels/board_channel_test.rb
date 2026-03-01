# frozen_string_literal: true

require "test_helper"

class BoardChannelTest < ActionCable::Channel::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @board = create(:board, project: @project)

    stub_connection current_user: @user
  end

  test "subscribes to board when user is project member" do
    subscribe(board_id: @board.id)
    assert subscription.confirmed?
    assert_has_stream_for @board
  end

  test "rejects subscription when board not found" do
    subscribe(board_id: 0)
    assert subscription.rejected?
  end

  test "rejects subscription when user cannot access project" do
    other_company = create(:company)
    other_user = create(:user, company: other_company)
    stub_connection current_user: other_user

    subscribe(board_id: @board.id)
    assert subscription.rejected?
  end

  test "broadcast_event sends data to board stream" do
    subscribe(board_id: @board.id)

    assert_broadcast_on(@board, {
      "type" => "task_created",
      "data" => { "id" => 1, "title" => "Test" },
      "actor_id" => @user.id
    }) do
      BoardChannel.broadcast_event(@board, "task_created", { "id" => 1, "title" => "Test" }, actor_id: @user.id)
    end
  end
end
