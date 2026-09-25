# frozen_string_literal: true

require "test_helper"

# The in-container git helper asks here for every fetch and push of a GitHub or
# GitLab repository, instead of the token living in the checkout's remote.
class GitCredentialsTest < ActionDispatch::IntegrationTest
  PATH = "/agents/git/credentials"

  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @integration = create(:integration, company: @company, connected_by: @user, status: :active)
    @repo = create(:repository, full_name: "acme/api", integration: @integration, scope: @project)
    @session = create(:terminal_session, :agent_session, :running, user: @user, project: @project)
    @session.repositories << @repo
    @tokens = FakeGithub::TokenService.new(token: "ghs_narrow")
    Github::TokenService.stubs(:new).returns(@tokens)
  end

  def ask(repository_id: @repo.id, url: "https://github.com/acme/api.git", key: GitCredentials::SessionKey.generate(@session))
    post PATH, params: { repository_id: repository_id, url: url }.to_json,
               headers: { "X-Session-Id" => @session.id.to_s, "X-Git-Key" => key, "CONTENT_TYPE" => "application/json" }
  end

  test "vends a token narrowed to the attached repository, and nothing keeps a copy" do
    ask

    assert_response :success
    assert_equal({ "username" => "x-access-token", "password" => "ghs_narrow" }, response.parsed_body)
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_equal [ [ "api" ] ], @tokens.calls_to(:generate_installation_token).map { |c| c[:repositories] }
  end

  test "refuses without the session's own key" do
    ask(key: "nope")
    assert_response :unauthorized

    other = create(:terminal_session, :agent_session, :running, user: @user, project: @project)
    ask(key: GitCredentials::SessionKey.generate(other))
    assert_response :unauthorized
  end

  test "refuses a repository the session does not have" do
    stranger = create(:repository, full_name: "acme/other", integration: @integration, scope: @project)

    ask(repository_id: stranger.id, url: "https://github.com/acme/other.git")

    assert_response :forbidden
    assert_not @tokens.called?(:generate_installation_token)
  end

  # A rewritten remote must not turn one repository's credential into another's.
  test "refuses a URL that is not the repository's own" do
    ask(url: "https://evil.example/acme/api.git")
    assert_response :forbidden

    ask(url: "https://github.com/acme/other.git")
    assert_response :forbidden
  end

  test "stops vending once the session has ended or its owner has left" do
    @session.update!(state: "finished")
    ask
    assert_response :unauthorized

    @session.update!(state: "running")
    @user.company_memberships.find_by(company: @company).update_columns(state: "revoked")
    ask
    assert_response :unauthorized
  end
end
