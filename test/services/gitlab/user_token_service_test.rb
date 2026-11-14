# frozen_string_literal: true

require "test_helper"

# Contract tests: the real Gitlab::UserTokenService against GitLab's payloads.
# FakeGitlab::UserTokenService returns the shapes pinned here.
class Gitlab::UserTokenServiceTest < ActiveSupport::TestCase
  API = "https://gitlab.com/api/v4"
  # GitLab's OAuth access tokens are long; the gem sends 64 characters or more as Bearer.
  TOKEN = "glo-#{'a' * 64}".freeze

  setup do
    @service = Gitlab::UserTokenService.new
  end

  def json(body = nil, status: 200, **fields)
    { status: status, body: (body || fields).to_json, headers: { "Content-Type" => "application/json" } }
  end

  test "user returns the identity with the address GitLab commits with" do
    stub_request(:get, "#{API}/user").with(headers: { "Authorization" => "Bearer #{TOKEN}" }).to_return(json(
      id: 456, username: "lab-user", name: "Lab User", avatar_url: "https://a.test/456",
      commit_email: "456-lab-user@users.noreply.gitlab.com", email: "private@example.com"
    ))

    assert_equal({ id: 456, username: "lab-user", name: "Lab User", avatar_url: "https://a.test/456",
                   commit_email: "456-lab-user@users.noreply.gitlab.com" }, @service.user(TOKEN))
  end

  test "a token of 64 characters or more goes as a Bearer header and never as a PRIVATE-TOKEN" do
    stub = stub_request(:get, "#{API}/user")
           .with { |request| request.headers["Authorization"] == "Bearer #{TOKEN}" && request.headers["Private-Token"].nil? }
           .to_return(json(id: 456, username: "lab-user", name: "Lab User"))

    @service.user(TOKEN)

    assert_requested stub
  end

  test "user leaves commit_email nil when GitLab sends none" do
    stub_request(:get, "#{API}/user").to_return(json(id: 456, username: "lab-user", name: "Lab User"))

    assert_nil @service.user(TOKEN)[:commit_email]
  end

  test "project_access is the larger of project and group access" do
    stub_request(:get, "#{API}/projects/group%2Fsub%2Fapp").to_return(json(
      id: 9, permissions: { project_access: { access_level: 20 }, group_access: { access_level: 40 } }
    ))

    assert_equal 40, @service.project_access(TOKEN, "group/sub/app")
  end

  test "project_access is nil for a project the person cannot see" do
    stub_request(:get, "#{API}/projects/group%2Fapp").to_return(json({ message: "404 Project Not Found" }, status: 404))

    assert_nil @service.project_access(TOKEN, "group/app")
  end

  test "project_access asks the member list when the project reports less than Developer" do
    stub_request(:get, "#{API}/projects/group%2Fapp").to_return(json(id: 9, permissions: { project_access: nil, group_access: nil }))
    stub_request(:get, "#{API}/projects/9/members/all").with(query: { "user_ids" => [ "456" ] })
                                                       .to_return(json([ { id: 456, access_level: 30 } ]))

    assert_equal 30, @service.project_access(TOKEN, "group/app", user_id: 456)
  end

  test "project_access is nil when neither the project nor its members show access" do
    stub_request(:get, "#{API}/projects/group%2Fapp").to_return(json(id: 9, permissions: { project_access: nil, group_access: nil }))
    stub_request(:get, "#{API}/projects/9/members/all").with(query: { "user_ids" => [ "456" ] })
                                                       .to_return(json([]))

    assert_nil @service.project_access(TOKEN, "group/app", user_id: 456)
  end

  test "a network failure is Unavailable" do
    stub_request(:get, "#{API}/user").to_timeout

    assert_raises(Gitlab::UserTokenService::Unavailable) { @service.user(TOKEN) }
  end

  test "errors map to InvalidToken, Forbidden and Unavailable without a body or token" do
    stub_request(:get, "#{API}/user").to_return(json({ message: "401 Unauthorized glo-token" }, status: 401)).then
                                     .to_return(json({ message: "nope" }, status: 403)).then
                                     .to_return(json({ error: "x" }, status: 503))

    assert_raises(Gitlab::UserTokenService::InvalidToken) { @service.user(TOKEN) }
    assert_raises(Gitlab::UserTokenService::Forbidden) { @service.user(TOKEN) }
    error = assert_raises(Gitlab::UserTokenService::Unavailable) { Gitlab::UserTokenService.new.user(TOKEN) }
    assert_not_includes error.message, TOKEN
  end
end
