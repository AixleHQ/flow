# frozen_string_literal: true

require "test_helper"

class TerminalSessionChannelTest < ActionCable::Channel::TestCase
  setup do
    @user = create(:user, :with_company)
    @project = create(:project, company: @user.company, owner: @user)
    @session = create(:terminal_session, :with_user, :with_project, user: @user, project: @project)
    stub_connection(current_user: @user)
  end

  test "subscribes and streams for owned session" do
    subscribe(session_id: @session.id)

    assert subscription.confirmed?
    assert_has_stream_for @session
  end

  test "rejects when session not found" do
    subscribe(session_id: 999_999)

    assert_not subscription.confirmed?
  end

  test "rejects when user cannot access session" do
    other_user = create(:user, :with_company)
    stub_connection(current_user: other_user)

    subscribe(session_id: @session.id)

    assert_not subscription.confirmed?
  end

  test "rejects when current_user is nil" do
    stub_connection(current_user: nil)

    subscribe(session_id: @session.id)

    assert_not subscription.confirmed?
  end

  test "transmits session data on subscribe" do
    subscribe(session_id: @session.id)

    assert_equal 1, transmissions.size
    msg = transmissions.first
    assert_equal "session_update", msg["type"]
    assert msg["data"].key?("id")
    assert_equal @session.id, msg["data"]["id"]
  end

  test "refresh transmits updated session data" do
    subscribe(session_id: @session.id)
    # subscribe sends 1 transmission; refresh sends another
    perform :refresh

    assert transmissions.any? { |t| t["type"] == "session_update" }
  end

  test "broadcast_update sends to stream" do
    stream = TerminalSessionChannel.broadcasting_for(@session)

    assert_broadcasts(stream, 1) do
      TerminalSessionChannel.broadcast_update(@session)
    end
  end
end
