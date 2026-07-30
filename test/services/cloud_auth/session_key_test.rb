# frozen_string_literal: true

require "test_helper"

module CloudAuth
  class SessionKeyTest < ActiveSupport::TestCase
    setup do
      @company = create(:company)
      @user = create(:user, :admin, company: @company)
      @project = create(:project, company: @company, owner: @user)
      @session = create(:terminal_session, :running, user: @user, project: @project)
      @other = create(:terminal_session, :running, user: @user, project: @project)
    end

    test "generate is deterministic for a session" do
      assert_equal SessionKey.generate(@session), SessionKey.generate(@session)
    end

    test "generate differs per session" do
      assert_not_equal SessionKey.generate(@session), SessionKey.generate(@other)
    end

    test "the key is not the session's mcp_key or route_token" do
      key = SessionKey.generate(@session)

      assert_not_equal @session.mcp_key, key
      assert_not_equal @session.route_token, key
    end

    test "valid? accepts the matching key and rejects everything else" do
      assert SessionKey.valid?(@session, SessionKey.generate(@session))
      assert_not SessionKey.valid?(@session, SessionKey.generate(@other))
      assert_not SessionKey.valid?(@session, "nope")
      assert_not SessionKey.valid?(@session, "")
      assert_not SessionKey.valid?(@session, nil)
      assert_not SessionKey.valid?(nil, SessionKey.generate(@session))
    end

    test "the key is derived from the app key base, not stored on the session" do
      assert_not_includes @session.attributes.values.map(&:to_s), SessionKey.generate(@session)
      assert_equal 32, SessionKey.secret.bytesize
    end
  end
end
