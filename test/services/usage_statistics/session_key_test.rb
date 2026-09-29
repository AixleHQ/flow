# frozen_string_literal: true

require "test_helper"

module UsageStatistics
  class SessionKeyTest < ActiveSupport::TestCase
    test "a key validates only for the route token it was derived from" do
      key = SessionKey.generate("tok-a")

      assert SessionKey.valid?("tok-a", key)
      assert_not SessionKey.valid?("tok-b", key)
      assert_not SessionKey.valid?("tok-a", nil)
      assert_not SessionKey.valid?(nil, key)
    end

    test "is not the credential write-back key for the same session" do
      session = build(:terminal_session, id: 42, route_token: "tok-a")

      assert_not_equal Agents::SessionKey.generate(session), SessionKey.generate(session.route_token)
    end

    test "resource attributes carry the token and its key, and nothing for a session without one" do
      session = build(:terminal_session, route_token: "tok-a")

      assert_equal "terminal_session_token=tok-a,terminal_session_key=#{SessionKey.generate('tok-a')}",
                   SessionKey.resource_attributes(session)
      assert_nil SessionKey.resource_attributes(nil)
    end
  end
end
