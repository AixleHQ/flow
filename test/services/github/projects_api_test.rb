# frozen_string_literal: true

require "test_helper"

# Contract tests: the real Github::ProjectsApi against GitHub's documented
# GraphQL and REST payloads. FakeGithub::ProjectsApi returns the shapes pinned here.
class Github::ProjectsApiTest < ActiveSupport::TestCase
  GRAPHQL = "https://api.github.com/graphql"

  setup do
    @integration = create(:integration, :github_projects, :active)
    Github::TokenService.stubs(:new).returns(FakeGithub::TokenService.new)
    @api = Github::ProjectsApi.for(@integration)
  end

  def stub_graphql(data: nil, errors: nil, &matcher)
    request = stub_request(:post, GRAPHQL).with(headers: { "Authorization" => "Bearer #{FakeGithub::TokenService::DEFAULT_TOKEN}" })
    request = request.with { |req| matcher.call(JSON.parse(req.body)) } if matcher
    request.to_return(status: 200, body: { data: data, errors: errors }.compact.to_json, headers: { "Content-Type" => "application/json" })
  end

  ISSUE_NODE = {
    id: "I_kwDOissue1", number: 1, title: "It breaks", body: "Steps", url: "https://github.com/acme-corp/app/issues/1",
    state: "OPEN", stateReason: nil, updatedAt: "2026-10-01T10:00:00Z", repository: { nameWithOwner: "acme-corp/app" },
    issueType: { name: "Bug" }, assignees: { nodes: [ { login: "ada" } ] }, labels: { nodes: [ { name: "ai" } ] }
  }.freeze

  test "an organization's projects come back page by page" do
    stub_graphql(data: { organization: { projectsV2: { pageInfo: { hasNextPage: true, endCursor: "c1" },
                                                      nodes: [ { id: "PVT_1", number: 1, title: "Roadmap", url: "https://github.com/orgs/acme-corp/projects/1", closed: false } ] } } }) do |body|
      body.dig("variables", "after").nil?
    end
    stub_graphql(data: { organization: { projectsV2: { pageInfo: { hasNextPage: false, endCursor: nil },
                                                      nodes: [ { id: "PVT_2", number: 2, title: "Old", url: "u", closed: true } ] } } }) do |body|
      body.dig("variables", "after") == "c1" && body.dig("variables", "login") == "acme-corp"
    end

    assert_equal [ { id: "PVT_1", number: 1, title: "Roadmap", url: "https://github.com/orgs/acme-corp/projects/1", closed: false },
                   { id: "PVT_2", number: 2, title: "Old", url: "u", closed: true } ], @api.projects("acme-corp")
  end

  test "a project comes back with its status field's options" do
    stub_graphql(data: { node: { id: "PVT_1", number: 1, title: "Roadmap", url: "u", owner: { login: "acme-corp" },
                                 field: { id: "PVTSSF_1", name: "Status", options: [ { id: "f75ad846", name: "Todo" } ] } } }) do |body|
      body.dig("variables", "field") == "Status"
    end

    assert_equal({ id: "PVT_1", number: 1, title: "Roadmap", url: "u", owner: "acme-corp",
                   field: { id: "PVTSSF_1", name: "Status", options: [ { id: "f75ad846", name: "Todo" } ] } },
                 @api.project("PVT_1", field: "Status"))
  end

  test "an issue comes back with the boards it is on and its column on each" do
    stub_graphql(data: { node: ISSUE_NODE.merge(projectItems: { nodes: [
      { id: "PVTI_1", project: { id: "PVT_1" }, fieldValueByName: { name: "Ready for AI", optionId: "opt-ready" } },
      { id: "PVTI_2", project: { id: "PVT_2" }, fieldValueByName: nil }
    ] }) })

    assert_equal({
      id: "I_kwDOissue1", number: 1, key: "acme-corp/app#1", url: "https://github.com/acme-corp/app/issues/1",
      title: "It breaks", body: "Steps", state: "OPEN", state_reason: nil, type: "Bug", pull_request: false,
      repository: "acme-corp/app", updated_at: "2026-10-01T10:00:00Z", assignees: [ "ada" ], labels: [ "ai" ],
      placements: [ { item_id: "PVTI_1", project_id: "PVT_1", status: "Ready for AI", option_id: "opt-ready" },
                    { item_id: "PVTI_2", project_id: "PVT_2", status: nil, option_id: nil } ]
    }, @api.content("I_kwDOissue1", field: "Status"))
  end

  test "an unknown node is nil, not an error" do
    stub_graphql(data: { node: nil })

    assert_nil @api.content("I_nope", field: "Status")
  end

  test "a board's items skip drafts, which match neither issue nor pull request" do
    stub_graphql(data: { node: { items: { pageInfo: { hasNextPage: true, endCursor: "n2" }, nodes: [
      { id: "PVTI_1", project: { id: "PVT_1" }, fieldValueByName: { name: "Todo", optionId: "o1" }, content: ISSUE_NODE },
      { id: "PVTI_3", project: { id: "PVT_1" }, fieldValueByName: nil, content: {} }
    ] } } }) do |body|
      body.dig("variables", "query") == "-is:draft" && body.dig("variables", "first") == 50
    end

    result = @api.items("PVT_1", query: "-is:draft", field: "Status", limit: 50)

    assert_equal [ "acme-corp/app#1" ], result[:items].pluck(:key)
    assert_equal [ { item_id: "PVTI_1", project_id: "PVT_1", status: "Todo", option_id: "o1" } ], result[:items].first[:placements]
    assert_equal "n2", result[:next_cursor]
  end

  test "a permission GitHub has not granted says which ones the App needs" do
    stub_graphql(data: { organization: nil },
                 errors: [ { type: "FORBIDDEN", message: "Resource not accessible by integration", path: [ "organization" ] } ])

    error = assert_raises(Trackers::Error) { @api.projects("acme-corp") }
    assert_equal "permission_denied", error.code
    assert_match(/Projects \(organization\) and Issues \(repository\)/, error.message)
  end

  test "moving a card sends the option to the item's field" do
    stub_graphql(data: { updateProjectV2ItemFieldValue: { projectV2Item: { id: "PVTI_1" } } }) do |body|
      body["variables"] == { "project" => "PVT_1", "item" => "PVTI_1", "field" => "PVTSSF_1", "option" => "opt-ready" }
    end

    assert @api.set_status(project_id: "PVT_1", item_id: "PVTI_1", field_id: "PVTSSF_1", option_id: "opt-ready")
  end

  test "a write GitHub did not answer is an unknown outcome, a read a timeout" do
    stub_request(:post, GRAPHQL).to_timeout

    assert_raises(Trackers::Error::OutcomeUnknown) { @api.add_comment("I_1", "hi") }
    assert_equal "timeout", assert_raises(Trackers::Error) { @api.content("I_1", field: "Status") }.code
  end

  test "an issue is created through REST and answers its node id and key" do
    stub_request(:post, "https://api.github.com/repos/acme-corp/app/issues")
      .with(body: { title: "New", body: "Body", assignees: [ "ada" ], labels: [ "ai" ], type: "Bug" }.to_json)
      .to_return(status: 201, body: { id: 1, node_id: "I_kwDOnew", number: 42 }.to_json)

    assert_equal({ node_id: "I_kwDOnew", key: "acme-corp/app#42" },
                 @api.create_issue("acme-corp/app", title: "New", body: "Body", assignees: [ "ada" ], labels: [ "ai" ], type: "Bug"))
  end

  test "REST refusals keep GitHub's reason, and a spent rate limit is not a permission problem" do
    stub_request(:patch, "https://api.github.com/repos/acme-corp/app/issues/1")
      .to_return(status: 422, body: { message: "Validation Failed", errors: [ { field: "assignees", code: "invalid" } ] }.to_json)
    stub_request(:put, "https://api.github.com/repos/acme-corp/app/issues/1/labels")
      .to_return(status: 403, body: { message: "API rate limit exceeded" }.to_json, headers: { "x-ratelimit-remaining" => "0" })
    stub_request(:delete, "https://api.github.com/repos/acme-corp/app/issues/1/labels/needs%20review").to_return(status: 404, body: "{}")

    error = assert_raises(Trackers::Error) { @api.update_issue("acme-corp/app", 1, { assignees: [ "x" ] }) }
    assert_equal [ "validation_failed", "Validation Failed: assignees invalid" ], [ error.code, error.message ]
    assert_equal "rate_limited", assert_raises(Trackers::Error) { @api.set_labels("acme-corp/app", 1, [ "ai" ]) }.code
    assert_nil @api.remove_label("acme-corp/app", 1, "needs review")
  end
end
