# frozen_string_literal: true

require "test_helper"

# Contract tests: the real Gitlab::TrackerApi and Gitlab::Rest against GitLab's
# REST payloads. FakeGitlab::TrackerApi returns the shapes pinned here.
class Gitlab::TrackerApiTest < ActiveSupport::TestCase
  API = "https://gitlab.com/api/v4"

  setup do
    @api = Gitlab::TrackerApi.new(Gitlab::Rest.new(token: "glpat-x", retry_delay: 0))
  end

  def json(body, headers = {}) = { status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" }.merge(headers) }

  test "an issue is keyed by its project and iid, with GitLab's own reference" do
    stub_request(:get, "#{API}/projects/501/issues/1").with(headers: { "Authorization" => "Bearer glpat-x" }).to_return(json(
      id: 9001, iid: 1, project_id: 501, title: "It breaks", description: "Steps", state: "opened", issue_type: "issue",
      labels: [ "Ready for AI", "bug" ], assignees: [ { id: 11, username: "ada", name: "Ada" } ], confidential: false,
      web_url: "https://gitlab.com/acme/app/-/issues/1", references: { full: "acme/app#1" }, updated_at: "2026-10-20T10:00:00Z"
    ))

    assert_equal({
      id: "501:1", global_id: "9001", iid: 1, project_id: "501", key: "acme/app#1", url: "https://gitlab.com/acme/app/-/issues/1",
      title: "It breaks", description: "Steps", state: "opened", type: "issue", labels: [ "Ready for AI", "bug" ],
      assignees: [ { id: "11", username: "ada", name: "Ada" } ], confidential: false, updated_at: "2026-10-20T10:00:00Z"
    }, @api.issue("501", 1))
  end

  test "a board keeps its label lists in board order and drops lists of another kind" do
    stub_request(:get, "#{API}/projects/501/boards").to_return(json([ { id: 71, name: "Development", lists: [
      { id: 2, label: { name: "Doing" }, position: 1 }, { id: 1, label: { name: "Ready for AI" }, position: 0 },
      { id: 3, assignee: { username: "ada" }, position: 2 }
    ] } ]))

    assert_equal [ { id: "71", name: "Development", lists: [ "Ready for AI", "Doing" ] } ], @api.boards("501")
  end

  test "notes leave GitLab's system notes out and say which are internal" do
    stub_request(:get, "#{API}/projects/501/issues/1/notes").with(query: hash_including("sort" => "asc")).to_return(json([
      { id: 5, body: "changed the description", system: true, author: { username: "ada" } },
      { id: 6, body: "see [log](/uploads/aa/log.txt)", system: false, internal: true, author: { username: "ada" }, created_at: "t" }
    ]))

    notes = @api.notes("501", 1, page: 1, per_page: 100)[:notes]

    assert_equal [ { id: "6", body: "see [log](/uploads/aa/log.txt)", author: "ada", created_at: "t", internal: true } ], notes
  end

  test "a list follows GitLab's next-page header" do
    stub_request(:get, "#{API}/projects/501/members/all").with(query: hash_including("page" => "1"))
      .to_return(json([ { id: 11, username: "ada", name: "Ada" } ], "X-Next-Page" => "2"))
    stub_request(:get, "#{API}/projects/501/members/all").with(query: hash_including("page" => "2"))
      .to_return(json([ { id: 12, username: "adam", name: "Adam" } ], "X-Next-Page" => ""))

    assert_equal %w[ada adam], @api.members("501").pluck(:username)
  end

  test "a hook is registered for issue and note events with our token" do
    hook = stub_request(:post, "#{API}/projects/501/hooks")
             .with { |r| JSON.parse(r.body).values_at("token", "issues_events", "note_events", "push_events") == [ "s3cret", true, true, false ] }
             .to_return(json(id: 44))

    assert_equal "44", @api.create_hook("501", url: "https://flow.test/webhooks/trackers/x", token: "s3cret")
    assert_requested hook
  end

  test "an upload answers with the secret and name its Markdown link uses, and downloads by them" do
    resolve_hosts_publicly!
    stub_request(:post, "#{API}/projects/501/uploads").to_return(json(
      id: 3, alt: "run", url: "/uploads/#{'a' * 32}/run%20log.txt", full_path: "/-/project/501/uploads/#{'a' * 32}/run%20log.txt",
      markdown: "[run log.txt](/uploads/#{'a' * 32}/run%20log.txt)"
    ))
    stub_request(:get, "#{API}/projects/501/uploads/#{'a' * 32}/run%20log.txt").with(headers: { "Authorization" => "Bearer glpat-x" })
      .to_return(status: 200, body: "log")
    file = Trackers::UploadFile.new(io: StringIO.new("log"), filename: "run log.txt", content_type: "text/plain", size: 3, sha256: "x")
    io = StringIO.new

    uploaded = @api.upload("501", file)
    @api.download("501", uploaded[:secret], uploaded[:filename], io: io, max_bytes: 1.megabyte)

    assert_equal [ "a" * 32, "run log.txt" ], uploaded.values_at(:secret, :filename)
    assert_equal "log", io.string
  end

  test "GitLab's refusals keep their meaning" do
    stub_request(:get, "#{API}/projects/501/issues/9").to_return(status: 404, body: { message: "404 Not found" }.to_json)
    stub_request(:put, "#{API}/projects/501/issues/1").to_return(status: 403, body: { message: "403 Forbidden" }.to_json)
    stub_request(:post, "#{API}/projects/501/issues/1/notes").to_return(status: 502)

    assert_equal "not_found", assert_raises(Trackers::Error) { @api.issue("501", 9) }.code
    assert_equal "permission_denied", assert_raises(Trackers::Error) { @api.update_issue("501", 1, { title: "x" }) }.code
    assert_raises(Trackers::Error::OutcomeUnknown) { @api.add_note("501", 1, "x") }
  end
end
