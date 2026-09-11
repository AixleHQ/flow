# frozen_string_literal: true

require "test_helper"

# The in-container git credential helper pipes this response into git's
# credential protocol. The authorization chain it depends on is asserted here
# rather than in a unit test because the endpoint is what an attacker reaches.
class AzureGitCredentialsTest < ActionDispatch::IntegrationTest
  PATH = "/azure/git/credentials"

  setup do
    with_azure_devops_enabled
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @integration = create(:integration, :azure_devops, :active, company: @company, connected_by: @user)
    @project = @integration.project
    @repository = create(:repository, :azure_devops, integration: @integration, scope: @project)
    @session = create(:terminal_session, :running, user: @user, project: @project)
    @session.repositories << @repository
    stub_azure_token(tenant_id: @integration.azure_devops_installation.tenant_id, token: "git-token")
  end

  # == authentication ==

  test "vends a bearer credential to a live session holding the repository" do
    post PATH, params: { repository_id: @repository.id }, headers: headers

    assert_response :success
    body = response.parsed_body
    assert_equal "bearer", body["scheme"]
    assert_equal "git-token", body["password"]
    assert body["expires_in"].positive?
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "rejects a request with no key" do
    post PATH, params: { repository_id: @repository.id }, headers: { "X-Session-Id" => @session.id.to_s }

    assert_response :unauthorized
  end

  # The whole reason this endpoint does not reuse the session's mcp_key: that key
  # is handed INTO the container as the aixle-tools MCP header, so the
  # agent-driven process holds it. If it were accepted here, the credential
  # boundary would be a secret the model can read out of its own configuration.
  test "rejects the session's own mcp_key" do
    post PATH,
         params: { repository_id: @repository.id },
         headers: { "X-Session-Id" => @session.id.to_s, "X-Azure-Git-Key" => @session.mcp_key }

    assert_response :unauthorized
  end

  test "rejects another session's derived key" do
    other = create(:terminal_session, :running, user: @user, project: @project)

    post PATH,
         params: { repository_id: @repository.id },
         headers: { "X-Session-Id" => @session.id.to_s,
                    "X-Azure-Git-Key" => AzureDevops::GitSessionKey.generate(other) }

    assert_response :unauthorized
  end

  test "a finished session vends nothing" do
    @session.update!(state: "finished")

    post PATH, params: { repository_id: @repository.id }, headers: headers

    assert_response :unauthorized
  end

  # == authorization ==

  test "refuses a repository that is not attached to this session" do
    other_repository = create(:repository, :azure_devops, integration: @integration, scope: @project)

    post PATH, params: { repository_id: other_repository.id }, headers: headers

    assert_response :forbidden
    assert_equal "not_authorized", response.parsed_body["error"]
  end

  test "refuses a repository belonging to another project" do
    foreign_integration = create(:integration, :azure_devops, :active)
    foreign_repository = create(:repository, :azure_devops, integration: foreign_integration,
                                             scope: foreign_integration.project)
    # Attached to this session, but owned elsewhere: session membership alone is
    # not proof of project access.
    @session.repositories << foreign_repository

    post PATH, params: { repository_id: foreign_repository.id }, headers: headers

    assert_response :forbidden
  end

  test "refuses a non-Azure repository" do
    github_integration = create(:integration, :github, :active, company: @company, connected_by: @user)
    github_repository = create(:repository, integration: github_integration, scope: @project)
    @session.repositories << github_repository

    post PATH, params: { repository_id: github_repository.id }, headers: headers

    assert_response :forbidden
  end

  test "stops vending once the selected Azure project leaves the approved scope" do
    @integration.azure_devops_installation.update!(allowed_project_ids: [ SecureRandom.uuid ])

    post PATH, params: { repository_id: @repository.id }, headers: headers

    assert_response :forbidden
  end

  test "refuses a credential request for a different host" do
    post PATH,
         params: { repository_id: @repository.id, url: "https://evil.example.com/contoso/x/_git/api" },
         headers: headers

    assert_response :forbidden
  end

  test "an operator credential problem is not reported as a user authorization failure" do
    Settings.azure_devops.apps["default"]["client_secret"] = nil

    post PATH, params: { repository_id: @repository.id }, headers: headers

    assert_response :service_unavailable
    assert_equal "credential_action_required", response.parsed_body["error"]
  end

  private

  def headers(session: @session, key: nil)
    {
      "X-Session-Id" => session.id.to_s,
      "X-Azure-Git-Key" => key || AzureDevops::GitSessionKey.generate(session)
    }
  end
end
