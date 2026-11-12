# frozen_string_literal: true

require "test_helper"

class UserTokenIssuanceTest < ActiveSupport::TestCase
  setup do
    company = create(:company)
    @user = create(:user, :admin, company: company)
    @project = create(:project, company: company, owner: @user)
    @session = create(:terminal_session, :agent_session, user: @user, project: @project)
  end

  def issue(token)
    UserTokenIssuance.create!(terminal_session: @session, company: @project.company, project: @project,
                              acting_for_user: @user, session_user: @user, tool_name: "github_user_token",
                              provider: "github", token: token, target_login: "acme",
                              repository_full_names: [ "acme/flow" ])
  end

  test "the token round-trips and is stored encrypted" do
    issuance = issue("ghu_secret_value")

    assert_equal "ghu_secret_value", issuance.reload.token
    assert_not_includes issuance.encrypted_token, "ghu_secret_value"
  end

  test "the token is not shown by inspect" do
    issuance = issue("ghu_secret_value")

    assert_not_includes issuance.inspect, "ghu_secret_value"
    assert_not_includes issuance.inspect, issuance.encrypted_token
  end

  test "token_values_for lists the tokens of one session only" do
    issue("ghu_one")
    other = create(:terminal_session, :agent_session, user: @user, project: @project)
    UserTokenIssuance.create!(terminal_session: other, company: @project.company, project: @project,
                              acting_for_user: @user, tool_name: "github_user_token", provider: "github",
                              token: "ghu_other", target_login: "acme")

    assert_equal [ "ghu_one" ], UserTokenIssuance.token_values_for(@session)
  end
end
