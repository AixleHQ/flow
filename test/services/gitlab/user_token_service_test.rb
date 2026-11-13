# frozen_string_literal: true

require "test_helper"

# Contract tests: the real Gitlab::UserTokenService against GitLab's payloads.
# FakeGitlab::UserTokenService returns the shapes pinned here.
class Gitlab::UserTokenServiceTest < ActiveSupport::TestCase
  API = "https://gitlab.com/api/v4"

  setup do
    @service = Gitlab::UserTokenService.new
  end

  def json(body, status: 200) = { status: status, body: body.to_json, headers: { "Content-Type" => "application/json" } }

  test "user returns the identity with the address GitLab commits with" do
    stub_request(:get, "#{API}/user").with(headers: { "Authorization" => "Bearer glo-token" }).to_return(json(
      id: 456, username: "lab-user", name: "Lab User", avatar_url: "https://a.test/456",
      commit_email: "456-lab-user@users.noreply.gitlab.com", email: "private@example.com"
    ))

    assert_equal({ id: 456, username: "lab-user", name: "Lab User", avatar_url: "https://a.test/456",
                   commit_email: "456-lab-user@users.noreply.gitlab.com" }, @service.user("glo-token"))
  end

  test "user leaves commit_email nil when GitLab sends none" do
    stub_request(:get, "#{API}/user").to_return(json(id: 456, username: "lab-user", name: "Lab User"))

    assert_nil @service.user("glo-token")[:commit_email]
  end

  test "project_access is the larger of project and group access" do
    stub_request(:get, "#{API}/projects/group%2Fsub%2Fapp").to_return(json(
      id: 9, permissions: { project_access: { access_level: 20 }, group_access: { access_level: 40 } }
    ))

    assert_equal 40, @service.project_access("glo-token", "group/sub/app")
  end

  test "project_access is nil for a project the person cannot see" do
    stub_request(:get, "#{API}/projects/group%2Fapp").to_return(json({ message: "404 Project Not Found" }, status: 404))

    assert_nil @service.project_access("glo-token", "group/app")
  end

  test "project_access asks the member list when the project reports less than Developer" do
    stub_request(:get, "#{API}/projects/group%2Fapp").to_return(json(id: 9, permissions: { project_access: nil, group_access: nil }))
    stub_request(:get, "#{API}/projects/9/members/all/456").to_return(json(id: 456, access_level: 30))

    assert_equal 30, @service.project_access("glo-token", "group/app", user_id: 456)
  end

  test "project_access is nil when neither the project nor its members show access" do
    stub_request(:get, "#{API}/projects/group%2Fapp").to_return(json(id: 9, permissions: { project_access: nil, group_access: nil }))
    stub_request(:get, "#{API}/projects/9/members/all/456").to_return(json({ message: "404 Not found" }, status: 404))

    assert_nil @service.project_access("glo-token", "group/app", user_id: 456)
  end

  test "revoke posts the token with the app's credentials to GitLab" do
    Settings.gitlab.stubs(:oauth_client_id).returns("app-id")
    Settings.gitlab.stubs(:oauth_client_secret).returns("app-secret")
    stub = stub_request(:post, "https://gitlab.com/oauth/revoke")
           .with(body: { "client_id" => "app-id", "client_secret" => "app-secret", "token" => "glo-token" })
           .to_return(status: 200, body: "{}")

    assert @service.revoke("glo-token")
    assert_requested stub
  end

  test "revoke fails with Unavailable when GitLab refuses" do
    stub_request(:post, "https://gitlab.com/oauth/revoke").to_return(status: 500, body: "boom glo-token")

    error = assert_raises(Gitlab::UserTokenService::Unavailable) { @service.revoke("glo-token") }
    assert_not_includes error.message, "glo-token"
  end

  test "errors map to InvalidToken, Forbidden and Unavailable without a body or token" do
    stub_request(:get, "#{API}/user").to_return(json({ message: "401 Unauthorized glo-token" }, status: 401)).then
                                     .to_return(json({ message: "nope" }, status: 403)).then
                                     .to_return(json({ error: "x" }, status: 503))

    assert_raises(Gitlab::UserTokenService::InvalidToken) { @service.user("glo-token") }
    assert_raises(Gitlab::UserTokenService::Forbidden) { @service.user("glo-token") }
    error = assert_raises(Gitlab::UserTokenService::Unavailable) { Gitlab::UserTokenService.new.user("glo-token") }
    assert_not_includes error.message, "glo-token"
  end
end
