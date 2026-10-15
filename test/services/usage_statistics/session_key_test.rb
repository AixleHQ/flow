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

    test "resource attributes carry the token, its key and the agent type, and nothing for a session without one" do
      session = build(:terminal_session, route_token: "tok-a", agent_type: "claude_code")

      assert_equal "terminal_session_token=tok-a,terminal_session_key=#{SessionKey.generate('tok-a')},agent_type=claude_code",
                   SessionKey.resource_attributes(session)
      assert_nil SessionKey.resource_attributes(nil)
    end

    test "a key is required for every session, with no grandfather exemption" do
      # The route token is in every terminal URL, so trusting a batch by token
      # alone (the old pre-key exemption) let anyone who saw a URL forge usage.
      with_marker = build(:terminal_session, metadata: { SessionKey::LAUNCH_MARKER => 1 })
      without_marker = build(:terminal_session, metadata: {})

      assert SessionKey.required_for?(with_marker)
      assert SessionKey.required_for?(without_marker)
    end

    test "resource attributes omit the agent type when the session has none" do
      session = build(:terminal_session, route_token: "tok-a", agent_type: nil)

      assert_equal "terminal_session_token=tok-a,terminal_session_key=#{SessionKey.generate('tok-a')}",
                   SessionKey.resource_attributes(session)
    end

    test "resource attributes append Insights metadata after the internal pair when the integration is active" do
      session, integration = insights_session

      assert_equal "terminal_session_token=tok-a,terminal_session_key=#{SessionKey.generate('tok-a')}," \
                   "agent_type=claude_code,user_email=dev.ops+ci@example.com,project_name=Backend-API_v2," \
                   "proxy_enabled=true",
                   SessionKey.resource_attributes(session)
      refute_includes SessionKey.resource_attributes(session), integration.insights_ingest_token
    end

    test "resource attributes percent-encode Unicode, comma, equals, backslash and percent losslessly" do
      session, = insights_session(email: "üser+meta@example.com", project_name: "Проект, alpha=beta\\gamma%")

      raw = SessionKey.resource_attributes(session)
      pairs = raw.split(",").to_h { |pair| pair.split("=", 2) }

      assert_equal "%C3%BCser+meta@example.com", pairs.fetch("user_email")
      assert_equal "%D0%9F%D1%80%D0%BE%D0%B5%D0%BA%D1%82%2C%20alpha%3Dbeta%5Cgamma%25", pairs.fetch("project_name")
      assert_equal session.user.email, URI.decode_uri_component(pairs.fetch("user_email"))
      assert_equal session.project.name, URI.decode_uri_component(pairs.fetch("project_name"))
    end

    private

    def insights_session(email: "dev.ops+ci@example.com", project_name: "Backend-API_v2")
      company = create(:company)
      user = create(:user, company: company)
      project = create(:project, company: company, owner: user)
      user.update_column(:email, email)
      project.update_column(:name, project_name)
      integration = create(:integration, :insights, :active, company: company, project: project, connected_by: user)
      session = create(:terminal_session, user: user, project: project, agent_type: "claude_code", route_token: "tok-a")
      [ session, integration ]
    end
  end
end
