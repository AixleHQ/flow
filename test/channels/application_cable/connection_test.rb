# frozen_string_literal: true

require "test_helper"

module ApplicationCable
  class ConnectionTest < ActionCable::Connection::TestCase
    setup do
      @user = create(:user, :with_company)
    end

    test "connects with valid session and assigns current_user" do
      connect "/cable", params: { session_id: "test-session" }, session: { user_id: @user.id }

      assert_equal @user, connection.current_user
      assert_equal "test-session", connection.session_id
    end

    test "a connection without a signed-in user is refused" do
      assert_reject_connection { connect "/cable", params: { session_id: "other" } }
    end

    test "uses SecureRandom uuid for session_id when not in params" do
      connect "/cable", session: { user_id: @user.id }

      assert connection.session_id.present?
      assert_match(/\A[0-9a-f-]{36}\z/, connection.session_id)
    end
  end
end
