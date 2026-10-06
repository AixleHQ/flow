# frozen_string_literal: true

require "test_helper"

# Youtrack::Api against YouTrack's REST payloads; pins the shapes FakeYoutrack::Api returns (R4).
class Youtrack::ApiTest < ActiveSupport::TestCase
  BASE = "https://acme.youtrack.cloud"

  setup do
    resolve_hosts_publicly!
    @api = Youtrack::Api.new(Youtrack::Client.new(base_url: BASE, token: "perm:abc", retry_delay: 0))
  end

  def stub_get(path, body)
    stub_request(:get, %r{\A#{Regexp.escape(BASE)}#{Regexp.escape(path)}(\?|\z)}).to_return(status: 200, body: body.to_json)
  end

  test "who the token is, and the projects it sees without archived ones" do
    stub_get("/api/users/me", { id: "1-1", login: "aixle", fullName: "Aixle Bot", email: "bot@example.com", "$type": "Me" })
    stub_get("/api/admin/projects", [ { id: "0-1", shortName: "APP", name: "Application", archived: false },
                                      { id: "0-9", shortName: "OLD", name: "Old", archived: true } ])

    assert_equal({ id: "1-1", login: "aixle", name: "Aixle Bot", email: "bot@example.com" }, @api.me)
    assert_equal [ { id: "0-1", key: "APP", name: "Application" } ], @api.projects
  end

  test "a project's fields come with their values in board order and the people the user fields offer" do
    stub_get("/api/admin/projects/0-1/customFields", [
      { "$type": "StateProjectCustomField", field: { name: "State", fieldType: { id: "state[1]" } },
        bundle: { values: [ { id: "s2", name: "Fixed", isResolved: true, ordinal: 2 }, { id: "s1", name: "Open", isResolved: false, ordinal: 0 },
                            { id: "s3", name: "Gone", isResolved: true, ordinal: 3, archived: true } ] } },
      { "$type": "UserProjectCustomField", field: { name: "Assignee", fieldType: { id: "user[1]" } },
        bundle: { aggregatedUsers: [ { id: "1-2", login: "jdoe", fullName: "Jane Doe" }, { id: "1-9", login: "gone", banned: true } ] } }
    ])

    state, assignee = @api.project_fields("0-1")
    assert_equal [ "State", "state[1]", [ [ "Open", false ], [ "Fixed", true ] ] ],
                 [ state[:name], state[:field_type], state[:values].map { |v| v.values_at(:name, :resolved) } ]
    assert_equal [ { id: "1-2", login: "jdoe", name: "Jane Doe" } ], assignee[:users]
  end

  test "an issue is normalized with its custom fields, tags and reporter" do
    stub_get("/api/issues/APP-1", {
      id: "2-1", idReadable: "APP-1", summary: "It breaks", description: "Steps", created: 1_790_000_000_000, updated: 1_790_000_060_000,
      resolved: nil, project: { id: "0-1", shortName: "APP" }, reporter: { id: "1-2", login: "jdoe", fullName: "Jane Doe" },
      tags: [ { id: "6-1", name: "ai" } ],
      customFields: [
        { "$type": "StateIssueCustomField", name: "State", value: { "$type": "StateBundleElement", id: "s1", name: "Open", isResolved: false } },
        { "$type": "SingleUserIssueCustomField", name: "Assignee", value: { "$type": "User", id: "1-1", login: "aixle", fullName: "Aixle Bot" } },
        { "$type": "MultiEnumIssueCustomField", name: "Platforms", value: [ { name: "iOS" }, { name: "Web" } ] },
        { "$type": "SimpleIssueCustomField", name: "Points", value: 3 },
        { "$type": "TextIssueCustomField", name: "Notes", value: { "$type": "TextFieldValue", text: "hi" } }
      ]
    })

    issue = @api.issue("APP-1")
    assert_equal [ "2-1", "APP-1", "0-1", "APP", false, [ "ai" ], "jdoe" ],
                 [ issue[:id], issue[:key], issue[:project_id], issue[:project_key], issue[:resolved], issue[:tags].pluck(:name), issue.dig(:reporter, :login) ]
    assert_equal Time.zone.at(1_790_000_000).iso8601(3), issue[:created_at]
    values = issue[:custom_fields].to_h { |f| [ f[:name], f[:value] ] }
    assert_equal({ id: "s1", name: "Open", resolved: false }, values["State"])
    assert_equal "aixle", values["Assignee"][:login]
    assert_equal [ "iOS", "Web" ], values["Platforms"].pluck(:name)
    assert_equal [ 3, { text: "hi" } ], values.values_at("Points", "Notes")
  end

  test "field history newest first, with the names added and removed" do
    stub = stub_request(:get, %r{#{BASE}/api/issues/2-1/activities\?.*categories=CustomFieldCategory.*reverse=true})
           .to_return(status: 200, body: [ { id: "a-1", timestamp: 1_790_000_000_000, author: { id: "1-2", login: "jdoe" },
                                             field: { name: "State" }, added: [ { name: "Ready" } ], removed: [ { name: "Open" } ] },
                                           { id: "a-2", timestamp: 1_790_000_000_000, field: { presentation: "Assignee" },
                                             added: [ { login: "aixle" } ], removed: [] } ].to_json)

    state, assignee = @api.field_activities("2-1")
    assert_equal [ "a-1", "State", [ "Ready" ], [ "Open" ], "jdoe" ], [ state[:id], state[:field], state[:added], state[:removed], state.dig(:author, :login) ]
    assert_equal [ "Assignee", [ "aixle" ] ], [ assignee[:field], assignee[:added] ]
    assert_requested stub
  end

  test "a comment is read, a deleted one is gone, and one is added" do
    stub_get("/api/issues/2-1/comments/4-1", { id: "4-1", text: "@aixle go", created: 1_790_000_000_000, author: { login: "jdoe" } })
    stub_get("/api/issues/2-1/comments/4-2", { id: "4-2", deleted: true })
    added = stub_request(:post, %r{#{BASE}/api/issues/2-1/comments}).with(body: { text: "On it" }.to_json)
                                                                      .to_return(status: 200, body: { id: "4-3", text: "On it" }.to_json)

    assert_equal [ "@aixle go", "jdoe" ], @api.comment("2-1", "4-1").then { |c| [ c[:text], c.dig(:author, :login) ] }
    assert_nil @api.comment("2-1", "4-2")
    assert_equal "4-3", @api.add_comment("2-1", "On it")[:id]
    assert_requested added
  end
end
