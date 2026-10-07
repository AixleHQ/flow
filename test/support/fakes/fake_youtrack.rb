# frozen_string_literal: true

# In-memory fake of Youtrack::Api (docs/testing.md R3). Callers — the tracker
# provider, tools, the pipeline, the connect flow — get it from `stub_youtrack!`.
# The return shapes are the ones test/services/youtrack/api_test.rb pins the
# real adapter to against YouTrack's REST payloads (R4).
#
# Instance acme.youtrack.cloud: projects APP and OPS, and APP-1 in "Ready for AI".
module FakeYoutrack
  class Api
    BASE_URL = "https://acme.youtrack.cloud"
    APP = "0-1"
    OPS = "0-2"
    ISSUE_1 = "2-1"
    BOT = { id: "1-1", login: "aixle", name: "Aixle Bot", email: "bot@example.com" }.freeze
    USERS = [
      BOT,
      { id: "1-2", login: "jdoe", name: "Jane Doe", email: "jane@example.com" },
      { id: "1-3", login: "jdoe2", name: "John Doe", email: "john@example.com" }
    ].freeze
    PROJECTS = [ { id: APP, key: "APP", name: "Application" }, { id: OPS, key: "OPS", name: "Operations" } ].freeze
    STATES = [
      [ "Submitted", false ], [ "Ready for AI", false ], [ "In Progress", false ], [ "In Review", false ],
      [ "Fixed", true ], [ "Won't fix", true ]
    ].each_with_index.map { |(name, resolved), i| { id: "st-#{i}", name: name, resolved: resolved } }.freeze
    FIELDS = [
      { name: "State", field_type: "state[1]", values: STATES, users: [] },
      { name: "Type", field_type: "enum[1]", values: %w[Bug Task Feature].map { |n| { id: "ty-#{n}", name: n, resolved: false } }, users: [] },
      { name: "Priority", field_type: "enum[1]", values: %w[Normal Major Critical].map { |n| { id: "pr-#{n}", name: n, resolved: false } },
        users: [] },
      { name: "Assignee", field_type: "user[1]", values: [], users: USERS },
      { name: "Estimation", field_type: "period", values: [], users: [] }
    ].freeze
    TAGS = [ { id: "6-1", name: "ai" }, { id: "6-2", name: "backend" } ].freeze
    TYPES = {
      "State" => "StateIssueCustomField", "Type" => "SingleEnumIssueCustomField",
      "Priority" => "SingleEnumIssueCustomField", "Assignee" => "SingleUserIssueCustomField"
    }.freeze

    attr_reader :calls, :comments_by_issue, :activities
    attr_writer :me

    def initialize
      @calls = []
      @me = BOT.dup
      @issues = {}
      @comments_by_issue = Hash.new { |h, k| h[k] = [] }
      @activities = Hash.new { |h, k| h[k] = [] }
      @next = 100
      @failures = {}
      add_issue(id: ISSUE_1, key: "APP-1", title: "It breaks", state: "Ready for AI", project: PROJECTS[0])
      add_issue(id: "2-2", key: "OPS-1", title: "Rotate keys", state: "Submitted", project: PROJECTS[1])
    end

    def add_issue(id:, key:, title:, state:, project:, description: nil, type: "Bug", assignee: nil, tags: [],
                  created_at: Time.current.iso8601(3))
      @issues[id] = {
        id: id, key: key, title: title, description: description, created_at: created_at, updated_at: created_at,
        resolved: false, project_id: project[:id], project_key: project[:key], reporter: USERS[1].dup, tags: tags,
        custom_fields: [
          { name: "State", type: TYPES["State"], value: STATES.find { |s| s[:name] == state }.dup },
          { name: "Type", type: TYPES["Type"], value: { id: "ty-#{type}", name: type, resolved: false } },
          { name: "Priority", type: TYPES["Priority"], value: { id: "pr-Normal", name: "Normal", resolved: false } },
          { name: "Assignee", type: TYPES["Assignee"], value: assignee && USERS.find { |u| u[:login] == assignee }.dup }
        ]
      }
    end

    # A change someone made in YouTrack, as its history shows it.
    def record_activity(issue_id, field:, added:, removed: [], author: USERS[1], at: Time.current.iso8601(3))
      @activities[issue_id].unshift({ id: "act-#{@next += 1}", at: at, author: author.dup, field: field,
                                      added: Array(added), removed: Array(removed) })
    end

    def add_comment_by(issue_id, text:, author: USERS[1], created_at: Time.current.iso8601(3))
      comment = { id: "4-#{@next += 1}", text: text, created_at: created_at, author: author.dup }
      @comments_by_issue[issue_id] << comment
      comment.dup
    end

    def set_field(issue_id, name, value)
      @issues.fetch(issue_id)[:custom_fields].find { |f| f[:name] == name }[:value] = value
    end

    # The next call to `method` raises `error`.
    def fail_next(method, error)
      @failures[method] = error
    end

    def calls_to(method) = @calls.select { |c| c[:method] == method }
    def called?(method) = calls_to(method).any?

    def me = record(:me) { @me.dup }

    def projects = record(:projects) { PROJECTS.map(&:dup) }
    def project_fields(project_id) = record(:project_fields, project_id: project_id) { FIELDS.map(&:deep_dup) }
    def tags = record(:tags) { TAGS.map(&:dup) }

    def issue(ref)
      record(:issue, ref: ref) do
        found = @issues[ref.to_s] || @issues.values.find { |i| i[:key].casecmp?(ref.to_s) }
        found || raise(Trackers::Error.new("Issue not found", code: "not_found"))
        found.deep_dup
      end
    end

    def issues(query:, top:, skip:)
      record(:issues, query: query, top: top, skip: skip) do
        key = query[/\Aproject: \{([^}]+)\}/, 1]
        @issues.values.select { |i| i[:project_key] == key }.drop(skip).first(top).map(&:deep_dup)
      end
    end

    def create_issue(body)
      record(:create_issue, body: body) do
        project = PROJECTS.find { |p| p[:id] == body.dig(:project, :id) }
        id = "2-#{@next += 1}"
        add_issue(id: id, key: "#{project[:key]}-#{@next}", title: body[:summary], description: body[:description],
                  state: "Submitted", project: project, tags: TAGS.select { |t| Array(body[:tags]).any? { |r| r[:id] == t[:id] } })
        apply_fields(@issues[id], body[:customFields])
        @issues[id].deep_dup
      end
    end

    def update_issue(id, body)
      record(:update_issue, id: id, body: body) do
        issue = @issues.fetch(id)
        issue[:title] = body[:summary] if body.key?(:summary)
        issue[:description] = body[:description] if body.key?(:description)
        apply_fields(issue, body[:customFields])
        issue.deep_dup
      end
    end

    def add_tag(issue_id, tag_id)
      record(:add_tag, issue_id: issue_id, tag_id: tag_id) { @issues.fetch(issue_id)[:tags] |= TAGS.select { |t| t[:id] == tag_id } }
    end

    def remove_tag(issue_id, tag_id)
      record(:remove_tag, issue_id: issue_id, tag_id: tag_id) { @issues.fetch(issue_id)[:tags].reject! { |t| t[:id] == tag_id } }
    end

    def comments(issue_id, top:, skip:)
      record(:comments, issue_id: issue_id, top: top, skip: skip) { @comments_by_issue[issue_id].drop(skip).first(top).map(&:dup) }
    end

    def comment(issue_id, comment_id)
      record(:comment, issue_id: issue_id, comment_id: comment_id) do
        @comments_by_issue[issue_id].find { |c| c[:id] == comment_id }&.dup ||
          raise(Trackers::Error.new("Comment not found", code: "not_found"))
      end
    end

    def recent_comments(issue_id, top: 20)
      record(:recent_comments, issue_id: issue_id, top: top) { @comments_by_issue[issue_id].reverse.first(top).map(&:dup) }
    end

    def add_comment(issue_id, text)
      record(:add_comment, issue_id: issue_id, text: text) { add_comment_by(issue_id, text: text, author: BOT) }
    end

    def field_activities(issue_id, top: 50)
      record(:field_activities, issue_id: issue_id) { @activities[issue_id].first(top).map(&:deep_dup) }
    end

    private

    def apply_fields(issue, fields)
      Array(fields).each do |field|
        value = field[:value]
        value = if value.nil? then nil
        elsif value[:login] then USERS.find { |u| u[:login] == value[:login] }.dup
        elsif field[:name] == "State" then STATES.find { |s| s[:name] == value[:name] }.dup
        else { id: "v-#{value[:name]}", name: value[:name], resolved: false }
        end
        existing = issue[:custom_fields].find { |f| f[:name] == field[:name] }
        existing ? existing[:value] = value : issue[:custom_fields] << { name: field[:name], type: field[:$type], value: value }
      end
    end

    def record(method, **args)
      @calls << { method: method, **args }
      error = @failures.delete(method)
      raise error if error

      yield
    end
  end
end

# YouTrack in tests: `stub_youtrack!` hands every Youtrack::Api the one
# FakeYoutrack::Api it returns. Youtrack::Client stays real and is
# contract-tested against WebMock in test/services/youtrack/.
module YoutrackTestHelper
  def stub_youtrack!
    fake = FakeYoutrack::Api.new
    Youtrack::Api.stubs(:new).returns(fake)
    fake
  end

  # An event as the Aixle Flow app's rule builds it (youtrack-app/README.md, "Events").
  def youtrack_event(event, issue: "APP-1", project: "APP", **extra)
    { "version" => 1, "event" => event, "issue" => issue, "project" => project, "actor" => "jdoe",
      "at" => (Time.current.to_f * 1000).to_i }.merge(extra.stringify_keys)
  end
end
